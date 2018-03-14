ruleset errors {
	meta {
		author "Braden Hitchcock"
		description <<
			Error handling for wovyn temperature sensors
		>>
	}

	// Rule for catching and handling errors within the sensor manager pico 
	rule handle_error {
		select when sensor error_detected
		pre {
			error_domain = event:attr("domain")
			error_event = event:attr("event")
			error_message = event:attr("message")
		}
		send_directive("error_detected", {"domain": error_domain, "event": error_event,
										  "message": error_message})
	}
}