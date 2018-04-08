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
                      "events": []}
        // prepare_message(type)
        prepare_message = function(type){
            (type == "rumor") => 
                // Prepare a rumor message
                generate_rumor_message()
            |
                // Prepare a seen message response
                generate_seen_message({}, ent:state.keys())
        }

        create_my_message = function(){
            { "message_id": meta:picoId + ":" + ent:sequence_number,
              "sensor_id": meta:picoId,
              "temperature": ts:temperatures[0]{"temperature"},
              "timestamp": ts:temperatures[0]{"timestamp"}
            }
        }

        generate_rumor_message = function(peer_id){
            // The other half of the time we want to propogate a random message from others. This
            // message will be the latest gossip we have heard about a particular node
            peer_messages = ent:messages{ent:messages.keys()[random:integer(ent:messages.length() - 1)]};
            peer_messages[peer_messages.length() - 1]
        }

        generate_seen_message = function(peer_ids, seen){
            (peer_ids.length() == 0) => 
                seen 
            |
                generate_seen_message(peer_ids.tail(), 
                                      seen.put(peer_ids.head(), 
                                               ent:state{[peer_ids.head(), "received"]}[0]))
        }
        // get_peer(topic)
        // Determines the best peer to send the message to based on the message contents and what
        // the ruleset knows about the state of the peers
        get_peer = function(){
            add_score = function(remaining, scores){
                peer_id = engine:getPicoIDByECI(remaining.head(){"Tx"});
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

        get_received = function(peer_id){
            ent:state{[peer_id, "received"]}.defaultsTo([0])[0]
        }

        message_sorter = function(a, b){
            a_squence_number = a{"message_id"}.split(re#:#)[1].as("Number");
            b_sequence_number = b{"message_id"}.split(re#:#)[1].as("Number");
            a_squence_number < b_sequence_number => -1 |
            a_squence_number == b_sequence_number => 0 |
                                                     1
        }

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
            peer = get_peer()
            gossip_type = (random:integer(20) <= 10) => "rumor" | "seen"
            message = prepare_message(gossip_type)
        }
        // Send the message to the chosen subscriber on the gossip topic
        event:send({"eci": peer, "domain": "gossip", "type": gossip_type, "attrs": {
            "pico_id": meta:picoId,
            "message": message
        }})
        // Schedule the next heartbeat event
        always {
            // Generate a new message from me
            ent:messages{meta:picoId} := ent:messages{meta:picoId}.append([create_my_message()]);
            // Increment my send_sequence_number
            ent:send_sequence_number := ent:send_sequence_number + 1;
            // Schedule the next heartbeat event
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:interval})
        }
    }

    /** 
     * Receives a gossip from one of its peers, updating the internal state of this node and then
     * sending the message on to the next peer if there is one
     */
    rule gossip_rumor_message {
        select when gossip rumor
        pre {
            gossip_topic = event:attr("topic")
            message = event:attr("message")
            parts = message{"message_id"}.split(re#:#)
            peer_id = parts[0]
            sequence_number = parts[1].as("Number")
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
        always {
            ent:interval := 30;
            ent:topics := {};
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


}