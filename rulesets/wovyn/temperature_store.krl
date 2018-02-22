ruleset temperature_store {
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Persistent storage for temperature sensor results>>
        provides temperature, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function(){
            ent:temperatures.defaultsTo([])
        }
        threshold_violations = function(){
            ent:thresh_temperatures.defaultsTo([])
        }
        inrange_temperatures = function(){
            ent:temperatures.defaultsTo([]).filter(function(v){ent:thresh_temperatures >< v{"timestamp"}})
        }
    }
    
    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attr("temperature").klog("temperature")
            timestamp = event:attr("timestamp").klog("timestamp")
        }
        send_directive("collect_temperatures", {"temperature":temperature, "timestamp":timestamp})
        always {
            ent:temperatures := ent:temperatures.defaultsTo([]).append([{"timestamp":timestamp, "temperature":temperature}])
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            temperature = event:attr("temperature").klog("threshold violation temperature")
            timestamp = event:attr("timestamp").klog("threshold violation timestamp")
        }
        send_directive("collect_threshold_violations",
                        {"temperature":temperature,"timestamp":timestamp})
        always {
            ent:thresh_temperatures := ent:thresh_temperatures.defaultsTo([]).append([{"timestamp":timestamp, "temperature":temperature}])
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset
        send_directive("clear_temperature",{"body":"triggered"})
        always {
            clear ent:temperatures;
            clear ent:thresh_temperatures
        }
    }
}
