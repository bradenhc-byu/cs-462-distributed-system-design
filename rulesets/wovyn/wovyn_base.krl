ruleset wovyn_base {
    
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Base ruleset for temperature sensor>>
        use module sensor_profile alias sp
    }
    
    global {

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
        violation = event:attr("temperature") > sp:threshold()
      }
      if violation then
        send_directive("temperature_violation",{"temp":event:attr("temperature"), "threshold":ent:threshold.defaultsTo(thresholdDefault)})
      fired{
        raise wovyn event "threshold_violation"
          attributes {"temperature":event:attr("temperature"), "timestamp":event:attr("timestamp")}
      }
    }
    
    rule threshold_notification {
      select when wovyn threshold_violation
      pre{
        to_number = sp:contactNumber()
        from_number = sp:contactSource
        message = <<Temperature Violation Detected at #{event:attr("timestamp")}! 
Threshold: #{sp:threshold()}, 
Current: #{event:attr("temperature")}>>
      }
      if not sp:twilioEci().isnull() then
        event:send(
          {"eci": sp:twilioEci() , "eid": "threshold-notification",
           "domain": "twilio", "type": "new_message",
           "attrs": {"to":to_number, "from":from_number, "message":message} 
           }
        )
        //send_directive("threshold notiication sent", {"body":"The threshold notification has been sent"})
      notfired{
        raise twilio event "threshold_notification_failure"
          attributes {}
      }
    }

    rule threshold_notification_failure {
      select when wovyn threshold_notification_failure
      send_directive("threshold_notification_failure", {"message": "We failed to send your threshold 
        violation notification because the ECI for the Twilio Pico was null"})
    }
}
