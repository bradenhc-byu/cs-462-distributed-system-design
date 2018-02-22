ruleset sensor_profile {
	meta {
		author "Braden Hitchcock"
		description <<This ruleset is responsible for updating configuration of the Wovyn temperature sensor>>
		logging on
		provides threshold, contactNumber, location, sensorName, contactSource
		shares profile, threshold, contactNumber, location, sensorName
	}

	global {
		// Setting up some default values for the profile information
		defaultSensorName = "WovynTS"
		defaultLocation = {"longitude":-111.887991, "latitude":40.666892}
		defaultContactNumber = "+17208991356"
		defaultThreshold = 75
		contactSource = "+17206055306"
		// These are functions that this ruleset can provide to another ruleset when imported as a module.
		// They give access to the internal entity variabels to other rulesets.
		threshold = function(){
			ent:threshold.defaultsTo(defaultThreshold)
		}
		contactNumber = function(){
			ent:contact.defaultsTo(defaultContactNumber)
		}
		location = function(){
			ent:location.defaultsTo(defaultLocation)
		}
		sensorName = function(){
			ent:name.defaultsTo(defaultSensorName)
		}
		// This function provides all profile information to the caller
		profile = function(){
			{"name": ent:name.defaultsTo(defaultSensorName),
			 "contact": ent:contact.defaultsTo(defaultContactNumber),
			 "location": ent:location.defaultsTo(defaultLocation),
			 "threshold": ent:threshold.defaultsTo(defaultThreshold)}
		}
	}

	rule update_profile {
		select when sensor profile_updated
		pre {
			name = event:attr("name").klog("name")
			latitude = event:attr("location"){"latitude"}.as("Number").klog("location latitude")
			longitude = event:attr("location"){"longitude"}.as("Number").klog("location longitude")
			contact = event:attr("contact").klog("contact number")
			threshold = event:attr("threshold").as("Number").klog("threshold")
			exists = not name.isnull() && not latitude.isnull() && not longitude.isnull() && not contact.isnull() && not threshold.isnull()
		}
		if exists then send_directive("update_profile", {"message": "SUCCESS: update request received with the following values:",
														"name": name,
														"latitude": latitude,
														"longitude": longitude,
														"contact": contact,
														"threshold": threshold})
		fired {
			ent:name := name;
			ent:location := {"longitude": longitude, "latitude": latitude};
			ent:contact := contact;
			ent:threshold := threshold
		} else {
			send_directive("update_profile", {"message": "ERROR: failed to update profile due to incorrectly formatted request"})
		}
	}
}