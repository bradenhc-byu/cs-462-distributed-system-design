ruleset twilio.use {
  meta {
    use module twilio.keys alias keys
    use module twilio.send alias t
      with account_sid = keys:twilio("account_sid")
           auth_token = keys:twilio("auth_token")
  }

  rule send_new_sms {
    select when twilio new_message
    t:send_sms(event:attr("to"),
               event:attr("from"),
               event:attr("message")
               )
  }
}
