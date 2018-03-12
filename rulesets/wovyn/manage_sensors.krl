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
									 "twilio.keys", "twilio.api", "twilio.use",
									 "io.picolabs.subscription"]}
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
			valid = not sensor_id.isnull()
		}
		if valid then
			send_directive("store_child_sensor", {"sensor": sensor, "sensor_id": sensor_id})
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
			event:send(
				{"eci": subscription{"Tx"}, "eid": "initialize-profile",
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
			ent:sensors{sensor_pico_id} := ent:sensors{sensor_pico_id}.put(["Tx"],subscription{"Tx"})
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