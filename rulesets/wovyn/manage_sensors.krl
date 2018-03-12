ruleset manage_sensors {
	meta {
		author "Braden Hitchcock"
		description <<Main sensor management for other Wovyn TS picos>>
		logging on
		use module io.picolabs.wrangler alias wrangler
		use module io.picolabs.subscription alias subscription
		shares __testing, temperatures, children
	}

	global {
		// Establish some test cases 
		__testing = { "queries": [ {"name": "temperatures"},
								   {"name": "children"} ],
					  "events" : [ {"domain": "sensor", "type":"new_sensor", "attrs": ["sensor_id"]},
								   {"domain": "sensor", "type":"unneeded_sensor", "attrs":["sensor_id"]}]
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
		sensors = function(){
			ent:sensors.defaultsTo(defaultSensors)
		}
		// Retrieve all of the temperatures for the children 
		temperatures = function(){
			build_temperatures = function(child_list){
				( child_list.length() != 0 ) =>
						build_temperatures(child_list.tail()).put([child_list.head(){"name"}],
							http:get(meta:host + "/sky/cloud/" + child_list.head(){"eci"} +
								     "/temperature_store/temperatures"){"content"}.decode())
					|
						{}
			};
			build_temperatures(wrangler:children())
		}
		// Get all of the children of the pico 
		children = function(){
			wrangler:children()
		}
		// Get the wellKnown_Rx of a child pico 
		wellknown_rx = function(id){

			engine:listChildren(id).filter(function(c){c{"name"} == "wellKnown_Rx"})[0]{"id"}
		}
	}

	// Rule for handling when a user tries to add a new sensor that has the same
	// name as one that already exists
	rule sensor_already_exists {
		select when sensor new_sensor
		pre {
			sensor_id = event:attr("sensor_id").klog("sensor id")
			sensor_name = createNameFromID(sensor_id)
			exists = ent:sensors.defaultsTo(defaultSensors) >< sensor_name
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
			exists = ent:sensors.defaultsTo(defaultSensors) >< sensor_name
		}
		if not exists && valid then
			noop()
		fired {
			raise wrangler event "child_creation"
				attributes {"name": sensor_name, 
							"color": "#cccccc",
							"sensor_id": sensor_id,
							"rids": ["sensor_profile", "wovyn_base", "temperature_store",
									 "twilio.keys", "twilio.api", "twilio.use",
									 "io.picolabs.subscription"]}
		}
	}

	// Rule for storing a fully initialized sensor in the pico's entity variable
	// Before the sensor is stored, its default profile values will be set by the manager
	rule store_new_sensor {
		select when wrangler child_initialized
		pre {
			sensor = {"id": event:attr("id"), "eci": event:attr("eci")}
			sensor_id = event:attr("rs_attrs"){"sensor_id"}.klog("initialization complete for sensor")
			sensor_name = createNameFromID(sensor_id)
			valid = not sensor_id.isnull()
		}
		if valid.klog("valid request") then
			event:send(
				{"eci": sensor{"eci"}, "eid": "initialize-profile",
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
			ent:sensors := ent:sensors.defaultsTo(defaultSensors);
			ent:sensors{sensor_name} := sensor;
			// Now that we have stored it, we need to initiate a subscription 
			raise sensor event "subscribe_to_child"
				attributes {
					"child": {
						"id": sensor{"id"}, 
						"eci": subscription:wellKnown_Rx(sensor{"id"})
					}
				}
		}
	}

	// Rule for creating a subscription from this manager pico to a newly created child pico 
	rule create_subscription {
		select when sensor subscribe_to_child
		pre {
			child = event:attr("child")
		}
		if not child.isnull() then noop()
		fired {
			raise wrangler event "subscription" attributes
				{ "name" : "sensor-" + child{"id"},
		          "Rx_role": "sensor",
		          "Tx_role": "manager",
		          "channel_type": "subscription",
		          "wellKnown_Tx" : child{"eci"}
		       }
		}
	}

	// Rule for removing a sensor pico once it is no longer needed. After programmatically 
	// deleting it from the pico, it will also remove it from the internal entity storage
	rule remove_sensor_pico {
		select when sensor unneeded_sensor
		pre {
			sensor_id = event:attr("sensor_id")
			sensor_name = createNameFromID(sensor_id)
			exists = ent:sensors.defaultsTo(defaultSensors) >< sensor_name
		}
		if exists.klog("sensor to delete exists") then
			send_directive("deleting_sensor", {"name": sensor_name})
		fired {
			raise wrangler event "child_deletion"
				attributes {"name": sensor_name};
			clear ent:sensors{sensor_name}
		}
	}
}