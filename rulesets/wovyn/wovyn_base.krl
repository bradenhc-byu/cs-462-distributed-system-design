ruleset wovyn_base {
    
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Base ruleset for temperature sensor>>
    }
    
    global {
      temperature_threshold = 70
    }
    
    rule process_heartbeat {
        select when wovyn heartbeat
        pre {
          exists = (event:attr("genericThing").isnull() == false).klog("exists")
          temperature = ((exists) => event:attr("genericThing"){"data"}{"temperature"}[0]{"temperatureF"} | "NA").klog("temperature")
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
        violation = event:attr("temperature") > temperature_threshold
      }
      if violation then
        send_directive("temperature_violation",{"temp":event:attr("temperature"), "threshold":temperature_threshold})
      fired{
        raise wovyn event "temperature_threshold"
          attributes {"temperature":event:attr("temperature"), "timestamp":event:attr("timestamp")}
      }
    }
    
    rule threshold_notification {
      select when wovyn temperature_threshold
      pre{
        to = "+17208991356"
        from = "+17206055306"
        message = <<Temperature Violation Detected at #{event:attr("timestamp")}! 
Threshold: #{temperature_threshold}, 
Current: #{event:attr("temperature")}>>
      }
      send_directive("threshold notiication sent")
      fired{
        raise twilio event "new_message"
          attributes {"to":to, "from":from, "message":message}.klog("message attributes")
      }
    }
}
