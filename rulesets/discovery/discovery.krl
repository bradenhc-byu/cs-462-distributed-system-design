// TODO: This is currently just a stub for the service. Services still need to be implemented
ruleset pico.discovery {
	meta {
		name "Pico Discovery Service"
		description <<
			Core Pico Discovery Service Module
			[ use module pico.discovery alias discovery ]
			Discovery services are not currently built in to the pico engine core. This module has
			been developed to assist in the discovery of picos by their properties. It provides the
			following:
				- Service Registration
				- Service Discovery
			Picos MUST be explicity registered with this module in order to be discoverable by
			other picos.

			An example use case would be for identifying available services in the engine and
			being able to use those services or configure the dependent pico to use a default
			implementation of that service.
		>>
		author "Braden Hitchcock"
		logging on

	}

	global {
		// Define some test cases
		__testing = { "queries": [],
					  "events": []}
		//
		// -----------------------------------------------------------------------------------------
		// FUNCTIONS - available via module inclusion or the Sky Cloud API
		// -----------------------------------------------------------------------------------------
		//
		// discovery:register()
		//
		register = function(){

		}
		//
		// discovery:locate()
		//
		locate = function(){

		}
	}

	// ---------------------------------------------------------------------------------------------
	// RULES - internally
}