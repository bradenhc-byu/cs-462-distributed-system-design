ruleset twilio.send {

  meta {
    provides send_sms
    configure using
      account_sid = ""
      auth_token = ""
  }

  global{
    send_sms = defaction(to, from, message){
      base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>
      http:post(base_url + "Messages.json", form =
                    {"From":from,
                     "To":to,
                     "Body":message
                    })
    }
  }
}
