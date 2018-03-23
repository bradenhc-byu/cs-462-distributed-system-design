ruleset wovyn_base {
    
    meta {
        author "Braden Hitchcock"
        logging on
        description <<Base ruleset for temperature sensor>>
        use module sensor_profile alias sp
        use module temperature_store alias ts
        use module io.picolabs.subscription alias subscription
        shares __testing
    }
    
    global {
      __testing = {
        "queries": [

        ],
        "events": [
          {"domain": "wovyn", "type": "heartbeat", "attrs": ["genericThing"]} ,
          {"domain": "wovyn", "type": "temperature_report_request", "attrs": ["cid", "Tx"]}
        ]
      }
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
        send_directive("temperature_violation",{"temp":event:attr("temperature"), 
                                                "threshold":ent:threshold.defaultsTo(thresholdDefault)})
      fired{
        raise wovyn event "threshold_violation"
          attributes {"temperature":event:attr("temperature"), "timestamp":event:attr("timestamp")}
      }
    }
    
    rule threshold_notification {
      select when wovyn threshold_violation
      pre{
        name = sp:sensorName()
        timestamp = event:attr("timestamp")
        threshold = sp:threshold()
        temperature = event:attr("temperature")
        subscription_eci = subscription:established("Tx_role", "manager")[0]{"Tx"}
        valid = not timestamp.isnull() && not temperature.isnull()
      }
      if valid then
        event:send({
          "eci": subscription_eci, "eid": "threshold-notification",
          "domain": "sensor", "type": "threshold_notification",
          "attrs": {
            "sensor_name": name,
            "timestamp": timestamp,
            "temperature": temperature,
            "threshold": threshold
          }
        })
      notfired {
        raise sensor event "error_detected" attributes
          {"domain": "wovyn",
           "event": "threshold_violation",
           "message": "Unable to send a threshold notification due to null timestamp and/or " +
                      "temperature"}
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

  rule verify_added_subscription {
    select when wrangler subscription_added
    pre {
      subscription = event:attrs.klog("child subscription object")
      valid = not subscription.isnull()
    }
    if valid then
      send_directive("verify_added_subscription", {"subscription": subscription})
  }

  rule create_temperature_report {
    select when sensor temperature_report_request
    pre {
      report_id = event:attr("cid").klog("report id to create report for")
      eci = event:attr("Tx").klog("Tx for manager")
      temperatures = ts:temperatures().klog("temperatures")
    }
    event:send({"eci": eci,
               "eid": "report-created",
               "domain": "sensor",
               "type": "temperature_report_created",
               "attrs": {
                  "cid": report_id,
                  "name": sp:sensorName(),
                  "Tx": subscription:established("Tx", eci)[0]{"Rx"},
                  "temperatures": temperatures
                }})
  }
}
