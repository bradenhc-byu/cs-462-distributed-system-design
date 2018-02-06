ruleset wovyn_base {
    
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Base ruleset for temperature sensor>>
    }
    
    rule process_heartbeat {
        select when wovyn hearbeat
        send_directive("heartbeat",{"heartbeat":"lub-dub"})
    }
}
