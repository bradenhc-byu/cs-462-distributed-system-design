ruleset manage_sensors {
	meta {
		author "Braden Hitchcock"
		description <<Main sensor management for other Wovyn TS picos>>
		logging on
	}

	global {
		// Establish some default entity variable definitions
		defaultSensors = {}
		defaultThreshold = 80
		defaultLocation = {"longitude": 0.0, "latitude": 0.0}
		defaultContactNumber = "+17208991356"
		// Automatically generates a human readable name from a provided id
		createNameFromID = function(id){
			"Sensor " + id + " Pico"
		}
	}

	// Rule for handling when a user tries to add a new sensor that has the same
	// name as one that already exists
	rule sensor_already_exists {
		select when sensor new_sensor
		pre {
			sensor_id = event:attr("id").klog("sensor id")
			exists = ent:sensors >< sensor_id
		}
		if exists then
			send_directive("sensor_ready", {"sensor_id":sensor_id, "exists":true})
	}

	// Rule for adding a new sensor that doesn't already exist in the map
	// This will not only setup the name, id, and eci, but also install the required rulesets
	// for the pico to perform its tasks
	rule create_new_sensor {
		select when sensor new_sensor
		pre {
			sensor_id = event:attr("id").klog("sensor id")
			exists = ent:sensors >< sensor_id
		}
		if not exists then
			noop()
		fired {
			raise wrangler event "child_creation"
				attributes {"name": createNameFromID(sensor_id), 
							"color": "#cccccc",
							"sensor_id": sensor_id,
							"rids": ["sensor_profile", "wovyn_base", "temperature_store"]}
		}
	}

	// Rule for storing a fully initialized sensor in the pico's entity variable
	// Before the sensor is stored, its default profile values will be set by the manager
	rule store_new_sensor {
		select when wrangler child_initialized
		pre {
			sensor = {"id": event:attr("id"), "eci": event:attr("eci")}
			sensor_id = event:attr("rs_attrs"){"sensor_id"}
		}
		if sensor_id.klog("initialization complete for sensor") then
			event:send(
				{"eci": sensor{"eci"}, "eid": "initialize-profile",
				 "domain": "sensor", "type": "profile_updated",
				 "attrs": {"name": createNameFromID(sensor_id),
				 		   "contact": defaultContactNumber,
				 		   "location": defaultLocation,
				 		   "threshold": defaultThreshold 
				 		   } 
				 }
			)
		fired {
			ent:sensors := ent:sensors.defaultsTo(defaultSensors);
			ent:sensors{[sensor_id]} := sensor
		}
	}
}