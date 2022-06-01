require_relative "gateway.rb"

class SampleApp

  # NOTICE: THIS MUST BE A SESSION VARIABLE.
  # REPLACE THIS WITH A SESSION VARIABLE AS PROVIDED BY RAILS/SINATRA ETC.
  # THE BELOW WORKS FOR A SINGLE USER ONLY AND MAY PRESENT A SECURITY RISK
  @@threeDSRef = ""

#Circle4Take40Idea

  def call(env)
    gateway = Gateway.new(env, "100856", "Circle4Take40Idea")#, "https://test.3ds-pit.com/direct/", "https://test.3ds-pit.com/direct/")

    req = Rack::Request.new(env)

    if env["REQUEST_PATH"] == "/favicon.ico"
      return [404, { "Content-Type" => "text/html" }, ["No favicon"]]
    end

    body = ['<p> This is the sample code that demonstrates taking a 
    payment using the <a href="https://handpoint.com"> Handpoint </a> payment gateway. <br>
    Please <a href="/performTransaction"> click here </a> to carry out a test transaction <br>
    For debugging you may want do <a href="/showEnv"> see the environment varible </a>
    </p>']

    if env["REQUEST_PATH"] == "/performTransaction"
      if req.GET["acs"]
        # acs passed as a GET parameter. This indicates a response from the ACS
        # server within the IFrame. The below code simply POSTes the data back to
        # this script and removes the IFRAME Pass through all parameters for the sake of potential forwards compatibility.

        fields = {}
        req.POST.each { |k, v|
          fields["threeDSResponse[" + k + "]"] = v
        }

        body = [silentPost(getPageUrl(env), fields, "_parent")]
      else
        if !req.params.key?("browserInfo") && !req.params.key?("threeDSResponse")
          # We don't have any parameters, so this is the first request made.
          # The first thing we need to do is collect the browser's info.
          body = [gateway.collectBrowserInfo(env)]
        elsif req.params.key?("threeDSResponse")
          # Response from the 3DS Server, so the browser is returning from the 3DS server

          reqFields = {
            "action" => 'SALE',
            "threeDSRef" => @@threeDSRef,
          }

          req.POST["threeDSResponse"].each { |k, v|
            reqFields["threeDSResponse[" + k + "]"] = v
          }

          body = [processResponseFields(gateway.directRequest(reqFields), gateway)]
        else
          # Browser info present, but no threeDSResponse, this means it's the initial request to the gateway (not 3DS) server.
          reqFields = getInitialRequestFields(getPageUrl(env), env["REMOTE_ADDR"])
          reqFields.merge!(req.params["browserInfo"])
          body = [processResponseFields(gateway.directRequest(reqFields), gateway)]
        end
      end
    end

    [200, { "Content-Type" => "text/html" }, body]
  end

  def processResponseFields(responseFields, gateway)
    if responseFields.is_a?(Array)
      responseFields = Hash[responseFields]
    end
    responseCode = responseFields["responseCode"].to_i

    if responseCode == Gateway::RC_3DS_AUTHENTICATION_REQUIRED

      # Remember the threeDSRef, it's required when the ACS server responds.
      # THIS WILL NEED TO BE REMOVED.
      @@threeDSRef = responseFields["threeDSRef"]
      return showFrameForThreeDS(responseFields)
    elsif responseCode == Gateway::RC_SUCCESS
      return "<p>Thank you for your payment.</p>"
    else
      return "<p>Failed to take payment: " + HTMLEntities.new.encode(responseFields["responseMessage"]) + "</p>"
    end
  end

  def getInitialRequestFields(pageUrl, remoteAddress)
    uniqid = SecureRandom.alphanumeric(16)
    # E.g., '5f512348866d7'. This isn't strictly required, but it's often useful.

    fields = {
      "merchantID" => "100856",
      "action" => "SALE",
      "type" => 1,
      "transactionUnique" => uniqid,
      "countryCode" => 826,
      "currencyCode" => 826,
      "amount" => 1001,
      "cardNumber" => "4012001037141112",
      "cardExpiryMonth" => 12,
      "cardExpiryYear" => 15,
      "cardCVV" => "083",
      "customerName" => "Test Customer",
      "customerEmail" => "test@testcustomer.com",
      "customerAddress" => "30 Test Street",
      "customerPostcode" => "TE15 5ST",
      "orderRef" => "Test purchase",


      # The following fields are mandatory for 3DS v2
      "remoteAddress" => remoteAddress,
      "merchantCategoryCode" => 5411,
      "threeDSVersion" => "2",
      "threeDSRedirectURL" => pageUrl + "&acs=1",
    }
  end

  # Send a request to the ACS server by POSTing a form with the target set as the IFrame.
  # The form is hidden for threeDSMethodData requests (frictionless) and visible when the ACS
  # server may show a challenge to the user.  
  def showFrameForThreeDS(responseFields)


    p "Show frame..."
    p responseFields
    threeDSRequest = responseFields['threeDSRequest']
    
    if threeDSRequest.is_a?(Array)
      threeDSRequest = Hash[threeDSRequest]
    end

    style = threeDSRequest.key?("threeDSMethodData") ? "display: none;" : ""

    rtn = "<iframe name=\"threeds_acs\" style=\"height:420px; width:420px; #{style}\"></iframe>\n\n"

    # Silently POST the 3DS request to the ACS in the IFRAME
    rtn << silentPost(responseFields["threeDSURL"], responseFields['threeDSRequest'], "threeds_acs")

    return rtn
  end

    # NOTICE: THIS CODE WILL DEPEND ON YOUR DEPLOYMENT CONFIGURATION
  # This is providing the URL that's used in the html for the form, so it needs to be correct for
  # the public/external view of your application, the other side of any reverse proxy.

  # HTTP_X_FORWARDED_SERVER is provided by Apache when acting as reverse proxy. This is correct for rackup and Apache.
  def getPageUrl(env)
    if env.key?("HTTP_X_FORWARDED_SERVER")
      return "https://" + env["HTTP_X_FORWARDED_SERVER"] +
               env["REQUEST_URI"].gsub(/(sid=[^&]+&?)|(acs=1&?)/, "")
    end

    return (env["SERVER_PORT"] == "443" ? "https://" : "https://") +
             env["SERVER_NAME"] +
           (env["SERVER_PORT"] != "80" ? ":" + env["SERVER_PORT"] : "") +
             env["REQUEST_URI"].gsub(/(sid=[^&]+&?)|(acs=1&?)/, "")
  end

  def silentPost(url, fields, target = "_self")
    fieldsStr = ""
    fields.each { |k, v| fieldsStr << "<input type=\"hidden\" name=\"#{k}\" value=\"#{v}\" /> \n" }

    return (<<~SILENTFORM)
                  <form id="silentPost" action="#{url}" method="post" target="#{target}">
    #{fieldsStr}
                  <noscript><input type="submit" value="Continue"></noscript>
                  </form>
                  <script>
                      window.setTimeout('document.forms.silentPost.submit()', 0);
                  </script>
SILENTFORM
  end
end
