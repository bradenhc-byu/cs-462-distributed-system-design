ruleset temperature_store {
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Persistent storage for temperature sensor results>>
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        // Define some test cases
        __testing = { "queries": [],
                      "events": [{"domain": "wovyn", "type": "test_collect_temperatures", 
                                        "attrs":["temperature"]} 
                                ]
                    }
        temperatures = function(){
            ent:temperatures.defaultsTo([])
        }
        threshold_violations = function(){
            ent:thresh_temperatures.defaultsTo([])
        }
        inrange_temperatures = function(){
            ent:temperatures.defaultsTo([]).filter(function(v){ent:thresh_temperatures.index(v) == -1})
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
            ent:temperatures := [{"timestamp":timestamp, "temperature":temperature}].append(ent:temperatures.defaultsTo([]))
        }
    }

    rule test_collect_temperatures {
        select when wovyn test_collect_temperatures
        pre {
            temperature = event:attr("temperature").klog("testing by adding temperature")
            timestamp = time:now()
        }
        if not temperature.isnull() then noop()
        fired {
            ent:temperatures := [{"timestamp":timestamp, "temperature":temperature}].append(ent:temperatures.defaultsTo([])) 
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
            ent:thresh_temperatures := [{"timestamp":timestamp, "temperature":temperature}].append(ent:thresh_temperatures.defaultsTo([]))
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
