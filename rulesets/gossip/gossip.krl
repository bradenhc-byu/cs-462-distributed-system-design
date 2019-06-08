/** 
 * Gossip Protocol Ruleset
 * Braden Hitchcock
 * BYU CS 462 - Distributed System Design
 *
 * DISCLAIMER: This ruleset is meant to be a generic implementation of a gossip protocol. However,
 * currently it only handles gossiping about wovyn temperature sensor readings. The structure
 * seen in the entity variable below is the ultimate goal of the ruleset.
 *
 * This ruleset provides event handling for a simple gossip protocol among picos. The rules select
 * on events raised within the `gossip` domain.
 *
 * The following includes a description of the entity variables in this ruleset:
 *
 *  ent:topics = {
 *      "topic": {
 *          "send_sequence_number": 0,
 *          "state": {
 *              "peer_id": {
 *                  "peer_id": seen_sequence_number
 *              }
 *          },
 *          "rumor_messages": {
 *              "peer_id": [
 *                  { ... } // messages sorted by sequence number
 *              ]
 *          }
 *      }
 *  }
 *
 *  ent:interval = 30
 *
 * This ruleset uses subscriptions to determine who its neighbors are and how to send them
 * messages. The subscription role `gossip_node:<topic>` is used to do this, where topic is
 * the topic the node wants to gossip about
 */
ruleset gossip {
    meta {
        name "Gossip Protocol"
        author "Braden Hitchcock"
        description <<
            Gossip Service
            This service provides event handlers for gossiping information among peers. The internal
            data structures hold neighbor and message information. Messages are organized
            according to their topics in the data structures
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
                generate_seen_message({}, ent:topics{["wovynts", "rumor_messages"]}.keys())
        }

        generate_rumor_message = function(){
            // Half the time we want to send a new message from us 
            (random:integer(20) <= 10) =>
                { "message_id": meta:picoId + ":" + ent:topics{["wovynts", "send_sequence_number"]},
                  "sensor_id": meta:picoId,
                  "temperature": ts:temperatures[0]{"temperature"},
                  "timestamp": ts:temperatures[0]{"timestamp"}
                }
            |
            // The other half of the time we want to propogate a random message from others. This
            // message will be the latest gossip we have heard about a particular node 
                messages = ent:topics{["wovynts", "rumor_messages"]};
                peer_messages = messages{messages.keys()[random:integer(messages.length() - 1)]};
                peer_messages[peer_messages.length() - 1]
        }

        generate_seen_message = function(seen, peer_keys){
            (state.length() == 0) => 
                seen 
            |
                generate_seen_message(seen.put(peer_keys.head(), complete_sequence_number(peer_keys.head())), peer_keys.tail())
        }
        // get_peer(topic)
        // Determines the best to peer to send the message to based on the message contents and what
        // the ruleset knows about the state of the peers
        get_peer = function(topic, message){
            peers = subscription:established("Tx_role", "node");
            find_best = function(remaining, best_so_far){

            }
            find_best(peers.tail(), get_state_of_peer(peer{"Tx"}))
        }

        get_state_of_peer = function(eci){
            ent:topics{["wovynts", "state", engine:getPicoIDByECI(eci)]}
        }

        message_sorter = function(a, b){
            a_squence_number = a{"message_id"}.split(re#:#)[1].as("Number");
            b_sequence_number = b{"message_id"}.split(re#:#)[1].as("Number");
            a_squence_number < b_sequence_number => -1 |
            a_squence_number == b_sequence_number => 0 |
                                                     1
        }

        complete_sequence_number = function(peer_id){
            find_complete_sequence_number = function(messages, count){
                (message.length() == 0) => count - 1 |
                (messages.head(){"message_id"}.split(re#:#)[1].as("Number") == count) =>
                    find_complete_sequence_number(messages.tail(), count + 1) |
                    count - 1
            };
            find_complete_sequence_number(ent:topics.defaultsTo([]){["wovynts", "rumor_messages", peer_id]}, 0)
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
            gossip_type = (random:integer(20) <= 10) => "rumor" | "seen"
            message = prepare_message(gossip_type)
            peer = get_peer("wovynts", message)
        }
        // Send the message to the chosen subscriber on the gossip topic
        event:send("eci": peer, "domain": "gossip", "type": gossip_type, "attrs": {
            "topic": "wovynts",
            "message": message
        })
        // Schedule the next heartbeat event
        always {
            ent:topics{["wovynts", "send_sequence_number"} := ent:topics{["wovynts", "send_sequence_number"} + 1;
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
        select when wrangler ruleset_added where event:attr("rids").index("gossip") != -1
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