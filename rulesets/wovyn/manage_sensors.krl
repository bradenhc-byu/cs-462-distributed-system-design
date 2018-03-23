/**
 * Sensor Management
 * 
 * This ruleset contains shared functions and rules that control and manage a collection of
 * Wovyn temperature sensors.
 */
ruleset manage_sensors {
	meta {
		author "Braden Hitchcock"
		description <<Main sensor management for other Wovyn TS picos>>
		logging on
		use module io.picolabs.wrangler alias wrangler
		use module io.picolabs.subscription alias subscription
		shares __testing, temperatures, children, sensors, view_latest_report
	}

	global {
		// Establish some test cases 
		__testing = { "queries": [ {"name": "temperatures"},
								   {"name": "children"},
								   {"name": "sensors"} ],
					  "events" : [ {"domain": "sensor", "type":"new_sensor", 
					  									"attrs": ["sensor_id"]},
								   {"domain": "sensor", "type":"unneeded_sensor", 
								   						"attrs":["sensor_id"]},
								   {"domain": "sensor", "type":"introduce_sensor", 
								   						"attrs":["sensor_id", "eci"]}]
					}
		// Establish some default entity variable definitions
		defaultSensors = {}
		defaultThreshold = 80
		defaultLocation = {"longitude": 0.0, "latitude": 0.0}
		defaultContactNumber = "+17208991356"
		// Automatically generates a human readable name from a provided id
		createNameFromID = function(id){
			"Sensor " + id + " Pico"
		}
		// Returns the list of sensors registered with the sensor manager. The sensors are stored 
		// as a map in the following format:
		// {
		// 	"<pico id>": {
		//					"id": "<sensor id>",
		//					"eci": "<child eci>",
		//					"Tx": "<child subscription eci>"
		// 				 }
		// }
		sensors = function(){
			ent:sensors.defaultsTo(defaultSensors)
		}
		// Retrieve all of the temperatures for the children 
		temperatures = function(){
			build_temperatures = function(child_list){
				( child_list.length() != 0 ) =>
						build_temperatures(child_list.tail()).put([createNameFromID(getSensorByTx(child_list.head(){"Tx"}){"id"})],
							http:get(meta:host + "/sky/cloud/" + child_list.head(){"Tx"} +
								     "/temperature_store/temperatures"){"content"}.decode())
					|
						{}
			};
			build_temperatures(subscription:established("Tx_role", "sensor"))
		}
		// Get all of the children of the pico 
		children = function(){
			wrangler:children()
		}
		// Returns the child sensor information based on the Tx 
		getSensorByTx = function(Tx){
			ent:sensors{engine:getPicoIDByECI(Tx)}
		}
		// Generate a correlation identifier
		generateReportCorrelationId = function(){
			<<#{time:now()}::#{random:word()}>>
		}
		// Send the 5 latest reports 
		view_latest_report = function(){
			buildLatestReport(ent:reports.keys(), {})
		}
		// Build the latest reports recursively
		build_latest_report = function(report_keys, latest){
			(latest.length() == 5 || report_keys.length() == 0) => latest |
				buildLatestReport(report_keys.tail(), latest.put(report_keys.head(), 
													  ent:reports{report_keys.head()}))

		}
	}

	// Rule for handling when a user tries to add a new sensor that has the same
	// name as one that already exists
	rule sensor_already_exists {
		select when sensor new_sensor
		pre {
			sensor_id = event:attr("sensor_id").klog("sensor id")
			sensor_name = createNameFromID(sensor_id)
			exists = ent:sensors.defaultsTo(defaultSensors)
									.filter(function(x){x{"name"} == sensor_name})
									.keys().length() != 0
		}
		if exists then
			send_directive("sensor_ready", {"sensor_id":sensor_id, 
											"name": sensor_name,
										    "exists":true})
	}

	// Rule for adding a new sensor that doesn't already exist in the map
	// This will not only setup the name, id, and eci, but also install the required rulesets
	// for the pico to perform its tasks
	rule create_new_sensor {
		select when sensor new_sensor
		pre {
			sensor_id = event:attr("sensor_id").klog("sensor id")
			sensor_name = createNameFromID(sensor_id)
			valid = not sensor_id.isnull()
			exists = ent:sensors.defaultsTo(defaultSensors)
									.filter(function(x){x{"name"} == sensor_name})
									.keys().length() != 0
		}
		if not exists && valid then
			noop()
		fired {
			raise wrangler event "child_creation"
				attributes {"name": sensor_name, 
							"color": "#cccccc",
							"sensor_id": sensor_id,
							"rids": ["sensor_profile", "wovyn_base", "temperature_store",
									 "errors", "io.picolabs.subscription"]}
		}
	}

	// Rule for storing a fully initialized sensor in the pico's entity variable
	// After the sensor is stored, an event to create a subscription to the child will be raised
	rule store_child_sensor {
		select when wrangler child_initialized
		pre {
			sensor_pico_id = event:attr("id")
			sensor_pico_eci = event:attr("eci")
			sensor_id = event:attr("rs_attrs"){"sensor_id"}.klog("initialization complete for sensor")
			sensor_name = createNameFromID(sensor_id).klog("sensor name")
			valid = not sensor_id.isnull()
		}
		if valid then
			event:send(
				{"eci": sensor_pico_eci, "eid": "initialize-profile",
				 "domain": "sensor", "type": "profile_updated",
				 "attrs": {"name": sensor_name,
				 		   "contact": defaultContactNumber,
				 		   "location": defaultLocation,
				 		   "threshold": defaultThreshold,
				 		   "twilio_eci": defaultTwilioEci
				 		   } 
				 }
			)
		fired {
			// First store the child 
			ent:sensors := ent:sensors.defaultsTo(defaultSensors);
			ent:sensors{sensor_pico_id} := {"id": sensor_id, "eci": sensor_pico_eci};
			// Raise an event to subscribe to the child pico 
			raise wrangler event "subscription" attributes
				{ "name" : "sensor-" + sensor_id,
		          "Rx_role": "manager",
		          "Tx_role": "sensor",
		          "channel_type": "subscription",
		          "wellKnown_Tx" : sensor_pico_eci
		        }
		}
	}

	// After a subscription to the child has been created, we need to initialize it with default
	// profile data. 	
	rule initialize_child_profile {
		select when wrangler subscription_added
		pre {
			public_key = event:attr("_Tx_public_key").klog("public key")
			subscription = subscription:established("Tx_public_key", public_key)[0]
			sensor_pico_id = engine:getPicoIDByECI(subscription{"Tx"})
			sensor_name = createNameFromID(ent:sensors{sensor_pico_id}{"id"})
			valid = not subscription{"Tx"}.isnull()
		}
		if valid.klog("valid request") then
			noop()
		fired {
			ent:sensors{sensor_pico_id} := ent:sensors{sensor_pico_id}.put(["Tx"],subscription{"Tx"})
		}
	}

	// Rule used for introducing an already existing sensor pico to the sensor manager 
	rule introduce_existing_sensor {
		select when sensor introduce_sensor 
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
			ent:sensors := ent:sensors.defaultsTo(defaultSensors);
			ent:sensors{sensor_pico_id} := {"id": sensor_id, "eci": sensor_eci};
			// Raise an event to subscribe to the sensor pico 
			raise wrangler event "subscription" attributes
				{ "name" : "sensor-" + sensor_id,
		          "Rx_role": "manager",
		          "Tx_role": "sensor",
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

	// Rule for removing a child pico subscription when a sensor is no longer needed
	rule remove_sensor_pico_subscription {
		select when sensor unneeded_sensor
		pre {
			sensor = ent:sensors.defaultsTo(defaultSensors)
						.filter(function(x){x{"id"} == event:attr("sensor_id")})
						.values()[0]
			exists = not sensor.isnull()
		}
		if exists then
			send_directive("removing_child_subscription", {"name": createNameFromID(sensor{"id"})})
		fired {
			raise wrangler event "subscription_cancellation"
				attributes {"Tx": sensor{"Tx"}.klog("Tx of subscription to cancel")}
		}
	}

	// Rule for removing a sensor pico once it is no longer needed. After programmatically 
	// deleting it from the pico, it will also remove it from the internal entity storage
	rule remove_sensor_pico {
		select when wrangler subscription_removed
		pre {
			removed_Tx = event:attrs{["bus","Tx"]}.klog("removed subscription Tx")
			sensor = ent:sensors.defaultsTo(defaultSensors)
						.filter(function(x){x{"Tx"} == removed_Tx})
						.values()[0].klog("return from subscription removed")
			sensor_name = createNameFromID(sensor{"id"}).klog("sensor name")
			exists = not sensor.isnull()
		}
		if exists.klog("sensor to delete exists") then
			send_directive("deleting_sensor", {"name": createNameFromID(sensor{"id"})})
		fired {
			clear ent:sensors{engine:getPicoIDByECI(sensor{"eci"})};
			raise wrangler event "child_deletion"
				attributes {"name": sensor_name }	
		}
	}

	// Rule for generating a correlation identifier to be used in creating a temperature report.
	rule create_report_cid {
		select when sensor request_temperature_reports
		pre {
			report_id = generateReportCorrelationId().klog("new report cid")
		}
		if ent:reports >< report_id then noop()
		fired {
			raise sensor event "request_temperature_reports"
		} else {
			ent:reports := ent:reports.defaultsTo({});
			ent:reports{report_id} := { "sensors": ent:sensors.length(),
										"sent": 0,
										"received": 0,
										"temperatures": {}
									  };
			raise sensor event "scatter_temperature_report_requests"
				attributes {"cid": report_id }
		}
	}

	// Scatters a report request to all of the temperature sensor picos that are being managed by
	// this manager pico 
	rule scatter_report_request {
		select when sensor scatter_temperature_report_requests where not event:attr("cid").isnull()
		//foreach subscription:established("Tx_role", "sensor") setting(sensor)
		foreach ent:sensors setting(sensor_pico_id, sensor)
			always {
				raise sensor event "send_temperature_report_request"
					attributes {
						"cid": event:attr("cid"),
						"Tx": sensor{"Tx"}
					}
			}
	}

	// Sends a report request to a temperature sensor pico. We have abstracted this funcitonality
	// away so that we can ask for reports from individual temperature sensors without generating
	// a report for all of them
	rule send_single_temperature_report_request {
		select when sensor send_temperature_report_request
		event:send({"eci": event:attr("Tx"),
					   "eid": "get-temperatures",
					   "domain": "sensor",
					   "type": "temperature_report_request",
					   "attrs": {
					   		"Tx": subscription:established("Tx", event:attr("Tx")){"Rx"},
					   		"cid": event:attr("cid")
					   	}})
		fired {
			ent:reports{[event:attr("cid"), "sent"]} := ent:reports{[event:attr("cid"), "sent"]} + 1
		}
	}

	// Gathers the temperature reports sent back to the manager by the sensor picos 
	rule gather_temperature_reports {
		select when sensor temperature_report_created
		pre {
			report_id = event:attr("cid")
			sensor_Tx = event:attr("Tx")
			sensor_name = event:attr("name")
			valid = not report_id.isnull() && not sensor_Tx.isnull()
		}
		if valid then noop()
		fired {
			ent:reports{[report_id, "received"]} := ent:reports{[report_id, "received"]} + 1;
			ent:reports{[report_id, "temperatures", name]} := event:attr("temperatures");
			raise sensor event "check_temperature_report_status"
				attributes {
					"cid": report_id
				}
		}
	}

	rule check_temperature_report_status {
		select when sensor check_temperature_report_status
		pre {
			report = ent:reports{event:attr("cid")}
			report_complete = report{"sensors"} == report{"received"}
		}
		if report_complete then noop()
		fired {
			raise sensor event "temperature_report_data_ready"
				attributes event:attrs
		}
	}

	rule send_temperature_report {
		select when sensor temperature_report_data_ready
		send_directive("temperature_report", {"report_id": event:attr("cid"),
											  "report": ent:reports{event:attr("cid")}
											 }
					  )
	}
}