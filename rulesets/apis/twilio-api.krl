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
      http:post(base_url + "Messages.json", form =
                    {"From":from,
                     "To":to,
                     "Body":message
                    }.klog("form elements"))
    }
    messages = defaction(filter){
      base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com>>
      uri = (filter >< "next_page_uri" && filter{"next_page_uri"} != "") => filter{"next_page_uri"} | <</2010-04-01/Accounts/#{account_sid}/Messages/>>
      target = (filter >< "message_sid" && filter{"message_sid"} != "") => filter{"message_sid"} | ""
      query = {}
      query = (filter >< "to" && filter{"to"} != "") => query.put(["To"], filter{"to"}) | query
      query = (filter >< "from" && filter{"from"} != "") => query.put(["From"], filter{"from"}) | query
      response = http:get(base_url + uri + target + ".json", qs = query.klog("query"))
      content = response{"content"}.decode()
      send_directive("content", {"content":content}.klog("content"))
    }
  }

  rule on_post_success {
    select when http post
                 label re#twilio#
                 status_code re#(2\d\d)# setting (status)

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
