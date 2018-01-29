ruleset twilio.use {
  meta {
    author "Braden Hitchcock"
    logging on
    use module twilio.keys alias keys
    use module twilio.send alias t
      with account_sid = keys:twilio{"account_sid"}.klog("account sid")
           auth_token = keys:twilio{"auth_token"}.klog("authorization token")
  }

  rule send_new_sms {
    select when twilio new_message
    t:send_sms(event:attr("to"),
               event:attr("from"),
               event:attr("message")
               )
  }
}
