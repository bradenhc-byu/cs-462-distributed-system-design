ruleset sensor_notifications {
	meta {
		author "Braden Hitchcock"
		description <<
			Stores information relative to sending SMS notifications for threshold violations
			detected by the sensor manager
		>>
		logging on
	}

	global {
		// Declare some defaults
		defaultProfile = {"source_number": "+17206055306", "destination_number": "+17208991356"}
		// Message generator
		thresholdMessage = function(sensor, timestamp, temperature, th) {
			<<Threshold violation detected by #{sensor} at #{timestamp}: #{temperature} / #{th}>>
		}
	}

	// This rule updates the internal profile information for sending notifications 
	rule update_notification_profile {
		select when sensor update_notification_profile
		pre {
			destination_number = event:attr("to")
			source_number = event:attr("from")
			valid = not destination_number.isnull() && not source_number.isnull()
		}
		if valid then
			send_directive("update_notification_profile", {"status": "SUCCESS",
														   "destination_number": destination_number,
														   "source_number": source_number})
		fired {
			ent:profile := ent:profile.defaultsTo(defaultProfile);
			ent:profile{"source_number"} := source_number;
			ent:profile{"destination_number"} := destination_number
		}
		else {
			raise sensor event "error_detected" attributes
				{ "domain": "sensor",
				  "event": "update_notification_profile",
				  "message": "Invalid event:attrs structure"
				}
		}
	}

	// This rule sends a threshold notification using the Twilio API
	rule send_threshold_notification {
		select when sensor threshold_notification
		pre {
			sensor = event:attr("sensor_name")
			timestamp = event:attr("timestamp")
			temperature = event:attr("temperature")
			threshold = event:attr("threshold").defaultsTo("N/A")
			message = thresholdMessage(sensor, timestamp, temperature, threshold)
			valid = not sensor.isnull() && not timestamp.isnull() && not temperature.isnull()
		}
		if valid then 
			send_directive("threshold_notification", {"status": "SUCCESS",
													  "message": message})
		fired {
			raise twilio event "send_new_sms" attributes
				{ "to": ent:profile.defaultsTo(defaultProfile){"destination_number"},
				  "from": ent:profile.defaultsTo(defaultProfile){"source_number"},
				  "message": message }
		}
		else {
			raise sensor event "error_detected" attributes
				{ "domain": "sensor",
				  "event": "threshold_notification",
				  "message": "Failed to send notification message due to missing event attributes"
				}
		}
	}
}