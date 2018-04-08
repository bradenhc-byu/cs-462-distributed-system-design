/** 
 * Gossip Protocol Ruleset for Wovyn Temperature Sensors
 * Braden Hitchcock
 * BYU CS 462 - Distributed System Design
 *
 * This ruleset provides event handling for a simple gossip protocol among picos. The rules select
 * on events raised within the `gossip` domain.
 *
 * The following includes a description of the entity variables in this ruleset:
 *
 *  ent:send_sequence_number = 0
 * 
 *  ent:state = {
 *      "peer_id": {
 *          "seen": { ... }, // seen message from peer  
 *          received: [], // sequence numbers. This is only size of one normally 
 *      }
 *  }
 *
 *  ent:messages = {
 *      "pico_id": [
 *          { ... } // rumor message
 *      ]
 *  }
 *
 *  ent:interval = 30
 *
 *  ent:my_last_temperature_message = {}
 *
 * Subscription role: 'node'
 */
ruleset gossip {
    meta {
        name "TS Gossip Service"
        author "Braden Hitchcock"
        description <<
            This service provides event handlers for gossiping information among peers. The internal
            data structures hold neighbor and message information.
        >>    
        logging on
        use module temperature_store alias ts
        use module io.picolabs.subscription alias subscription
        shares __testing
    }

    global {
        // Define some test cases
        __testing = { "queries": [],
                      "events": [{"domain": "gossip", "type": "introduce_sensor", 
                                        "attrs":["sensor_id", "eci"]},
                                 {"domain": "gossip", "type": "heartbeat",
                                        "attrs":[]},
                                 {"domain": "gossip", "type": "rumor",
                                        "attrs":["message"]},
                                 {"domain": "gossip", "type": "interval",
                                        "attrs":["interval"]}]}
        /**
         * Entry function for preparing a message. It takes as an argument the type of message to
         * generate. This may either be 'rumor' or 'seen'
         */
        prepare_message = function(type){
            (type == "rumor") => 
                // Prepare a rumor message
                generate_rumor_message()
            |
                // Prepare a seen message response
                generate_seen_message({}, ent:state.keys())
        }

        /**
         * Uses the temperature_store ruleset to get the most recent temperature information for
         * this sensor pico. If there is temperature data in the store, then it will create a rumor
         * message and return it. Otherwise it will return null.
         */
        create_my_message = function(){
            ( not ts:temperatures[0].isnull() ) =>
                { "message_id": meta:picoId + ":" + ent:sequence_number,
                  "sensor_id": meta:picoId,
                  "temperature": ts:temperatures[0]{"temperature"},
                  "timestamp": ts:temperatures[0]{"timestamp"}
                }
            |
                null
        }

        /**
         * When we receive a heartbeat event, and the event type we are to produce is a 'rumor', 
         * then we need to randomely select a message containing most recent temperature information
         * to gossip to a peer. The peer will have been chosen beforehand.
         */
        generate_rumor_message = function(){
            // The other half of the time we want to propogate a random message from others. This
            // message will be the latest gossip we have heard about a particular node
            peer_messages = ent:messages{ent:messages.keys()[random:integer(ent:messages.length() - 1)]};
            peer_messages[peer_messages.length() - 1]
        }

        /**
         * When we receive a heartbeat event, and the event type we are to produce is a 'seen'
         * message, we will gather state information for the messages we have seen from all of our
         * peers and then send it to a pre-chosen peer. In return we would expect to receive all
         * of the information we may be missing that another peer has, although this secondary step
         * is not handled here in the function.
         */
        generate_seen_message = function(peer_ids, seen){
            (peer_ids.length() == 0) => 
                seen 
            |
                generate_seen_message(peer_ids.tail(), 
                                      seen.put(peer_ids.head(), 
                                               ent:state{[peer_ids.head(), "received"]}[0]))
        }

        /** 
         * Determines the best peer to send the message to. This is done by 'scoring' each peer.
         * We compare the states of other peers to our state. If they are missing messages that we
         * have, their score will be lower, whereas if they have messages we don't (which should
         * rarely be the case if the seen event is working properly), they score more points. At
         * the end of the algorithm, the peer with the lowest score is selected as the peer we
         * will send a message to.
         */
        get_peer = function(){
            add_score = function(remaining, scores){
                peer_id = engine:getPicoIDByECI(remaining.head(){"Tx"}).klog("peer id");
                score = get_score(peer_id);
                scores.append({"peer_id": peer_id, "score": score});
                calculate_scores(remaining.tail(), scores)
            };
            calculate_scores = function(remaining, scores){
                (remaining.length() == 0) =>
                    scores
                |
                    add_score(remaining, scores)
            };
            peers = subscription:established("Tx_role", "node");
            scores = calculate_scores(peers, []);
            set_best = function(scores, best){
                best = scores.head();
                find_best(scores.tail(), best)
            };
            find_best = function(scores, best){
                (scores.length() == 0) =>
                    best{"peer_id"}
                |
                (scores.head(){"score"} < best{"score"}) =>
                    set_best(scores, best)
                |
                    find_best(scores.tail(), best)
            };
            find_best(scores.tail(), scores.head()) 
        }

        /**
         * This is a helper function for finding the best peer to send a message to. It will
         * compare the state of the peer whose pico id it receives to our state and score it
         * according to the algorithm explained in the description of the get_peer() function.
         */
        get_score = function(peer_id){
            score = 0;
            // Compare my send sequence number with what they have for me
            score = score + ent:state{[peer_id, "seen", meta:picoId]}.defaultsTo(0) - ent:send_sequence_number;
            // Compare what I've seen to what they have seen and calculate the score
            add_score = function(seen, score){
                score = score + ent:state{[peer_id, "seen", seen.head()]} - get_received(seen.head());
                compare_seen(seen.tail(), score)
            };
            compare_seen = function(seen, score){
                (seen.length() == 0) =>
                    score
                |
                (seen.head() == meta:picoId) =>
                    compare_seen(seen.tail(), score)
                |
                    add_score(seen, score)
            };
            compare_seen(ent:state{[peer_id, "seen"]}.keys(), score)
        }

        /**
         * This will give us the highest, complete seen message sequence number we have from
         * a given peer. This helps us build the 'seen' message when we are gossiping about
         * our state to our peers.
         */
        get_received = function(peer_id){
            ent:state{[peer_id, "received"]}.defaultsTo([0])[0]
        }

        /**
         * This providers a sorter that will work on an array of rumor messages and order them
         * buy their sequence number. We are assuming that the arrays are already split up
         * by their peer ids, so we don't need to take those into accont when we are sorting.
         */
        message_sorter = function(a, b){
            a_squence_number = a{"message_id"}.split(re#:#)[1].as("Number");
            b_sequence_number = b{"message_id"}.split(re#:#)[1].as("Number");
            a_squence_number < b_sequence_number => -1 |
            a_squence_number == b_sequence_number => 0 |
                                                     1
        }

        /**
         * Stub for updating the state. Since this requires updating entity variables, we can't
         * do this here. Will remove eventually.
         */
        update_state = function(){
            null
        }
    }

    /** 
     * Gets the latest message information from this pico for the given topic and begins
     * gossiping about it to peers who are listening on the topic
     */
    rule gossip_heartbeat {
        select when gossip heartbeat
        pre {
            // Determine the type of message to gossip (seen or rumor)
            peer = get_peer().klog("peer selected")
            gossip_type = ((random:integer(20) <= 10) => "rumor" | "seen").klog("gossip type")
            message = prepare_message(gossip_type).klog("message")
            valid = not peer.isnull()
        }
        // Send the message to the chosen subscriber on the gossip topic
        if valid.klog("valid heartbeat") then
            event:send({"eci": peer, "domain": "gossip", "type": gossip_type, "attrs": {
                "pico_id": meta:picoId,
                "message": message
            }})
        // Schedule the next heartbeat event
        always {
            // Schedule the next heartbeat event
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:interval});
            // Attempt to add a new temperature to my storage
            raise gossip event "my_message_created" attributes 
                {"message": create_my_message()}
        }
    }

    rule add_my_message {
        select when gossip my_message_created where not event:attr("message").isnull()
        pre {
            // Make sure it isn't the same as our last message
            same_as_last = ent:my_last_temperature_message{"timestamp"} == event:attr("message"){"timestamp"}
            valid = not same_as_last
        }
        if valid.klog("can add message") then noop()
        fired {
            // Add it to our storage
            ent:messages{meta:picoId} := ent:messages{meta:picoId}.append([event:attr("message")]);
            // Increment my send_sequence_number
            ent:send_sequence_number := ent:send_sequence_number + 1;
            // Update our last message 
            ent:my_last_temperature_message := event:attr("message")
        }
    }

    /** 
     * Receives a gossip from one of its peers, updating the internal state of this node and then
     * sending the message on to the next peer if there is one
     */
    rule gossip_rumor_message {
        select when gossip rumor
        pre {
            message = event:attr("message").klog("message received from peer")
            parts = message{"message_id"}.split(re#:#)
            peer_id = parts[0].klog("peer id")
            sequence_number = parts[1].as("Number").klog("message sequence number")
        }
    }

    /**
     * Receives a seen message from one of its peers and responds by sending information the peer
     * does not have that this gossip node does
     */
    rule gossip_seen_message {
        select when gossip seen 
        pre {

        }
    }

    /**
     * Schedules the first gossip heartbeat event once this rulest has been installed
     */
    rule start_gossip {
        select when wrangler ruleset_added where rids >< meta:rid
        if ent:topics.isnull() || ent:interval.isnull() then noop()
        fired {
            ent:interval := 30;
            ent:send_sequence_number := 0;
            ent:my_last_temperature_message := {};
            ent:topics := {}
        }
        finally {
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:interval})
        }
    }

    /**
     * Event-based method for updating the interval entity variable
     */
    rule update_interval {
        select when gossip interval
        pre {
            interval = event:attr("interval")
        }
        if not interval.isnull() then
            send_directive("update_interval", { "value": interval })
        fired {
            ent:interval := interval
        }
    }

    /**
     * Rule used for introducing an already existing sensor pico to this gossip node
     */
    rule introduce_existing_sensor {
        select when gossip introduce_sensor 
        pre {
            sensor_id = event:attr("sensor_id").klog("sensor id")
            sensor_eci = event:attr("eci").klog("sensor eci")
            sensor_pico_id = engine:getPicoIDByECI(sensor_eci)
            valid = not sensor_id.isnull() && not sensor_eci.isnull()
        }
        if valid.klog("valid sensor introduction") then
            noop()
        fired {
            // First store the sensor 
            ent:state := ent:state.defaultsTo({});
            ent:state{sensor_pico_id} := {"seen": {}, "received": []};
            // Raise an event to subscribe to the sensor pico 
            raise wrangler event "subscription" attributes
                { "name" : "gossipSensor" + sensor_id,
                  "Rx_role": "node",
                  "Tx_role": "node",
                  "channel_type": "subscription",
                  "wellKnown_Tx" : sensor_eci
                }
        }
        else {
            raise sensor event "error_detected" attributes
                {"domain": "sensor",
                 "event": "introduce_sensor",
                 "message": "Invalid event attributes. Must include sensor id and eci."
                }
        }
    }

    // This rule will automatically accept any incoming subscription requests
    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        fired {
          raise wrangler event "pending_subscription_approval"
            attributes event:attrs
        }
    }


}