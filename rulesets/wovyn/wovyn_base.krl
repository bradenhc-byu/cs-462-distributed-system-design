ruleset wovyn_base {
    
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Base ruleset for temperature sensor>>
    }
    
    global {
      // we did use this before persistent variables were introduced. I added
      // an application variable that makes dynamically changing the threshold
      // easier, since global variables are not mutable
      // temperature_threshold = 75
    }
    
    rule process_heartbeat {
        select when wovyn heartbeat
        pre {
          exists = (event:attrs >< "genericThing").klog("exists")
          temperature = ((exists) => event:attrs{["genericThing","data","temperature",0,"temperatureF"]}.defaultsTo(-999.0) | "NA").klog("temperature")
          timestamp = time:now().klog("timestamp")
        }
        if exists then
          send_directive("heartbeat received",{"timestamp":timestamp, "temperature":temperature})
        fired {
          raise wovyn event "new_temperature_reading"
            attributes {"timestamp":timestamp,"temperature":temperature}
        } else {
          event:attr("genericThing").klog("thing")
        }
    }
    
    rule find_high_temps {
      select when wovyn new_temperature_reading
      pre {
        violation = event:attr("temperature") > app:threshold.defaultsTo(75)
      }
      if violation then
        send_directive("temperature_violation",{"temp":event:attr("temperature"), "threshold":app:threshold.defaultsTo(75)})
      fired{
        raise wovyn event "threshold_violation"
          attributes {"temperature":event:attr("temperature"), "timestamp":event:attr("timestamp")}
      }
    }
    
    rule threshold_notification {
      select when wovyn threshold_violation
      pre{
        to = "+17208991356"
        from = "+17206055306"
        message = <<Temperature Violation Detected at #{event:attr("timestamp")}! 
Threshold: #{app:threshold.defaultsTo(75)}, 
Current: #{event:attr("temperature")}>>
      }
      send_directive("threshold notiication sent", {"body":"The threshold notification has been sent"})
      fired{
        raise twilio event "new_message"
          attributes {"to":to, "from":from, "message":message}.klog("message attributes")
      }
    }
    
    rule change_threshold {
      select when wovyn threshold
      pre {
        temperature_threshold = event:attr("threshold").as("Number").klog("new threshold")
      }
      send_directive("change_threshold", {"value":temperature_threshold})
      always {
        app:threshold := temperature_threshold
      }
    }
}
