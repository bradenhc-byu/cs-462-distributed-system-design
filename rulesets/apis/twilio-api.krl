ruleset twilio.api {

  meta {
    author "Braden Hitchcock"
    logging on
    provides send_sms, messages
    configure using
      account_sid = ""
      auth_token = ""
  }

  global{
    send_sms = defaction(to, from, message){
      base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>.klog("post url")
      http:post(base_url + "Messages", form =
                    {"From":from,
                     "To":to,
                     "Body":message
                    }.klog("form elements"))
    }
    messages = defaction(message_sid, to , from){
      base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages>>
      target = (message_sid != "") => <</#{message_sid}>> | ""
      query = "?"
      query = (to == "") => <<#{query}&To=#{to}>> | query
      query = (from == "") => <<#{query}&From=#{from}>> | query
      http:get(base_url + target + query) setting(response)
    }
  }

  rule on_post_success {
    select when http post
                 label re#twilio#
                 status_code re#(2\d\d)# setting (status)
    send_directive("Status", {"status":"Success! The status is " + status}.klog("status"));
  }

  rule on_post_fail {
    select when http post
                 label re#twilio#
                 status_code re#([45]\d\d)# setting (status)
    fired {
      log error <<#{status}: #{event:attr("status_line")}>>;
      last;
    }
  }

}
