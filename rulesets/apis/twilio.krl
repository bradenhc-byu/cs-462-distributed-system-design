ruleset twilio {
  meta {
    use module twilio.keys alias keys
    use module twilio.send alias t
      with account_sid = keys:twilo("account_sid")
           auth_token = keys:twilo("auth_token")
  }

  rule test_send_sms {
    select when twilo new_message
    t:send_sms(event:attr("to"),
               event:attr("from"),
               event:attr("message")
               )
  }
}
