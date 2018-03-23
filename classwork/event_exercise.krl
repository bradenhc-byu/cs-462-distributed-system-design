/**
 * Event Expression Excercise
 * Braden Hitchcock
 * Blaine Backman
 */
/*
ruleset event_excercise {


	rule healthcare_tweet {
		select when tweet received
			body re#healthcare#gi
	}

	rule byu_football_email {
		select when email received
			subj re#byu#gi
			subj re#football#gi
	}

	rule mutiple_healthcare_tweet {
		select when count 4 tweet received
				body re#healthcare#gi
			within 4 hours 
	}

	rule tweet_and_email_healthcare {
		select when tweet received
			body re#healthcare#gi
		before email sent
			body re#healthcare#gi
			subj re#healthcare#gi
	}

	rule same_person_email {
		select when email received
				from re#(.*)# setting(name)
			before repeat(4, email received from re/#{name}/)
			within 20 minutes
	}

	rule stock_ticker_tweet {
		select when tweet received
				body re##gi
			and stock update
				change 
				percent > 2
			within 10 minutes
	}
}
*/