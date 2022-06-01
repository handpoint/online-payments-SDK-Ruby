require "uri"
require "net/http"
require "securerandom"
require "htmlentities"

class Gateway
  RC_SUCCESS = 0  # Transaction successful
  RC_DO_NOT_HONOR = 5  # Transaction declined
  RC_NO_REASON_TO_DECLINE = 85  # Verification successful

  RC_3DS_AUTHENTICATION_REQUIRED = 0x1010A # 3DS Authentication Required


  # Just the HTML entity encoder, used in a few places.
  @@coder = HTMLEntities.new

  def initialize(env, merchantId, merchantSecret, 
    directUrl = "https://gateway.handpoint.com/direct/", hostedUrl = "https://gateway.handpoint.com/hosted/",
    merchantPwd = nil, 
    proxyUrl = nil, proxyPort = nil)

    raise ArgumentError.new('env must be a Hash') unless env.is_a?(Hash)
    raise ArgumentError.new('merchantId must be a String') unless merchantId.is_a?(String)

    @merchantID = merchantId
    @merchantSecret = merchantSecret
    @merchantPwd = merchantPwd
    @env = env
    @directUrl = directUrl
    @hostedUrl = hostedUrl

    @proxyUrl = proxyUrl
    @proxyPort = proxyPort
  end


  # Send the request to the Gateway using the HTTP Direct API.
  # This method will attempt to sign the message before it's sent and verify the
  # response from the server.

  # request must be a hash of type string => (string|hash)

  # The request will use the following Gateway properties unless alternative
  # values are provided in the request;
  #  'directUrl'    - Gateway Direct API Endpoint
  #  'merchantID'    - Merchant Account Id or Alias
  #  'merchantPwd'  - Merchant Account Password (or null)
  #  'merchantSecret'  - Merchant Account Secret (or null)
  def directRequest(request, options = nil)

    raise ArgumentError.new('request must be a Hash') unless request.is_a?(Hash)

    requestSettings = {}

    p "Sending to server before it's processed"
    p request

    request = prepareRequest(request, nil, requestSettings)

    url = URI requestSettings['directUrl']

    if requestSettings['merchantSecret']
      request["signature"] = sign(request, requestSettings['merchantSecret'])
    end

    p "Sending to server AFTER it's processed"
    p request

    https = Net::HTTP.new(url.host, url.port, @proxyUrl, @proxyPort)
    https.use_ssl = true
    post = Net::HTTP::Post.new(url)

    post.form_data = request # PHP.http_build_query(request)

    httpResponse = https.request(post)

    responseBody = httpResponse.read_body()

    p responseBody

    response = URI.decode_www_form(responseBody)

    verifyResponse(response, requestSettings['merchantSecret'])

    response = restructureArray(response)

    return response
  end


  # Create a form that can then be used to send the request to the Gateway 
  # using the HTTP Hosted API.

  # request must be a hash of type string => (string|hash)
  # options should be a hash of string => string

  # The request will use the following Gateway properties unless alternative
  # values are provided in the request;
  # hostedUrl          - Gateway Hosted API Endpoint
  # merchantID         - Merchant Account Id
  # merchantPwd        - Merchant Account Password
  # merchantSecret'    - Merchant Account Secret
  
  # The method accepts the following options;
  # formAttrs     - HTML form attributes string
  # submitAttrs   - HTML submit button attributes string
  # submitImage   - URL of image to use as the Submit button
  # submitHtml    - HTML to show on the Submit button
  # submitText    - Text to show on the Submit button

  # 'submitImage', 'submitHtml' and 'submitText' are mutually exclusive
  # options and will be checked for in that order. If none are provided
  # the submitText='Pay Now' is assumed.
    
  # The prepareRequest method called within will throw an exception if there
  # key fields are missing, the method does not attempt to validate any request 
  # fields.

  # If the request doesn't contain a 'redirectURL' element then one will be
  # added which redirects the response to the current script.
  def hostedRequest(request, options = nil)
    raise ArgumentError.new('request must be a Hash') unless request.is_a?(Hash)

    requestSettings = {}
    prepareRequest(request, nil, requestSettings)

    if !request.key?("redirectURL")
      request["redirectURL"] = (env["HTTPS"] ? "https://" : "http://") + env["HTTP_HOST"] + env["REQUEST_URI"]
    end

    if requestSettings.key?("merchantSecret")
      request["signature"] = request.sign(request, requestSettings['merchantSecret'], request.keys)
    end

    ret = ""
    ret << '<form method="post" ' +
           options.key?("formAttrs") ? options["formAttrs"] : "" +
           ' action="' + @@coder.encode(requestSettings['hostedUrl']) + "\">\n"

    request.each do |name, value|
      ret << self.fieldToHtml(name, value)
    end

    if options.key?("submitAttrs")
      ret << options["submitAttrs"]
    end

    if options.key?("submitImage")
      ret << "<input " +
             (options.key?("submitAttrs") ? options["submitAttrs"] : "") +
             ' type="image" src="' + @@coder.encode(options["submitImage"]) + "\">\n"
    elsif options.key?("submitHtml")
      ret << '<button type="submit" ' +
             (options.key?("submitAttrs") ? options["submitAttrs"] : "") +
             ">{$options['submitHtml']}</button>\n"
    else
      ret << "<input " +
             (options.key?("submitAttrs") ? options["submitAttrs"] : "") +
             ' type="submit" value="' + (options.key?("submitText") ? @@coder.encode(options["submitText"]) : "Pay Now") + "\">\n"
    end

    ret << "</form>\n"
  end


  # Prepare a request for sending to the Gateway.
  #
  # The method will insert the following configuration properties into the
  # request if they are not already present;
  #   + 'merchantID'    - Merchant Account Id or Alias
  #   + 'merchantPwd'  - Merchant Account Password (or null)
  #
  # The method will throw an exception if the request doesn't contain an
  # 'action' element or a 'merchantID' element (and none could be inserted).
  #
  # request must be a hash of type string => (string|hash)
  # options  is not currently used
  # requestSettings is a hash container for merchantSecret, directUrl, and hostedUrl
  # which are either extracted from the request or the class.
  # This will raise ArgumentError if request or requestSettings are not Hashes. 
  #
  # The method does not attempt to validate any request fields.
  def prepareRequest(request, options, requestSettings)
    raise ArgumentError.new('request must be a Hash') unless request.is_a?(Hash)
    raise ArgumentError.new('requestSettings must be a Hash') unless requestSettings.is_a?(Hash)

    if not request.key?("action")
      raise RuntimeError, "Request must contain an 'action'."
    end
    
    if not request.key?("merchantID")
      if not @merchantID
        raise RuntimeError, "MerchantID not present in request or set in the Gateway class."
      end  

      request["merchantID"] = @merchantID
    end

    if (not request.key?("merchantPwd")) && @merchantPwd != nil
      request['merchantPwd'] = @merchantPwd
    end
    
    if request.key?('merchantSecret')
      requestSettings['merchantSecret'] = request['merchantSecret']
      request.delete('merchantSecret')
    elsif not @merchantSecret.to_s.empty? # nil.to_s == ""
      requestSettings['merchantSecret'] = @merchantSecret
    end

    requestSettings['hostedUrl'] = request.fetch('hostedUrl', @hostedUrl)
    request.delete('hostedUrl')

    requestSettings['directUrl'] = request.fetch('directUrl', @directUrl)
    request.delete('directUrl')

    keysToRemove = %w"responseCode responseMessage responseStatus state signature merchantAlias merchantID2"
    keysToRemove.each{|k| request.delete(k)}

    return request
  end

  # Sign the given array of data.
  # This method will return the correct signature for the data array
  # 
  # The partial parameter is used to indicate that the signature should
  # be marked as 'partial' and can takes an array of the keys to include
  # in the signature calculation. 
  def sign(data, secret = @merchantSecret, partial = [])
    raise ArgumentError.new('data must be a Hash or an Array') unless (data.is_a?(Hash) || data.is_a?(Array))
    raise ArgumentError.new('secret must be a String') unless secret.is_a?(String)

    partialStr = ""
    if partial.is_a? String 
      partial = partial.split(',')
    end

    if partial.is_a? Array and partial.length > 0
      data.select!(partial)
      partialStr = "|" + partial.join(',')
    end

    data = restructureArray(data)
    
    sorted_fields = Hash[data
        .filter { |key, value| value != nil }
        .sort_by { |key, value| 
          if key.include? '['
            key = key[..key.index('[') - 1]
          end 
          key
        }
    ]

    flattenedData = Hash[flattenArray(sorted_fields)]

    hashbody = http_build_query(flattenedData)

    hashbody.gsub!(/(%0D%0A|%0A%0D|%0D)/, "%0A")
    hashbody.gsub!("*", "%2A")
    hashbody.gsub!("~", "%7E")


    # partial is always empty in some deployments. This is fine. 
    return Digest::SHA512.hexdigest(hashbody + secret) + partialStr
  end


   # Verify the response.
   # 
   # This method will verify that the response is present, contains a response
   # code and is correctly signed.
   #
   # If the response is invalid then an exception will be thrown.
   #
   # Any signature is removed from the passed response.
   #
   # @param  array  $data    reference to the response to verify
   # @param  string  $secret    secret to use in signing
   # @return  boolean        true if signature verifies
  def verifyResponse(response, secret = @merchantSecret)
    #raise ArgumentError.new('response must be a Hash') unless 
    #  (response.is_a?(Hash) and response.key?("responseCode"))

    if response.is_a?(Hash)
      responseAry = []
      response.each{|k, v|
        responseAry.push([k, v])
      }

      response = responseAry
    end

    fields = nil
    signature = nil

    if response.assoc('signature')
        signatureArray = response.assoc('signature')
        signature = signatureArray[1]
        response.delete(signatureArray)

        if secret and signature and signature.index('|') != nil
          signature, fields = signature.split(',')
        end
    end

    ourSignature = sign(response, secret, fields)

    # We display three suitable different exception messages to help show
    # secret mismatches between ourselves and the Gateway without giving
    # too much away if the messages are displayed to the Cardholder.
    if !secret and signature
      # Signature present when not expected (Gateway has a secret but we don't)
      raise RuntimeError.new('Incorrectly signed response from Payment Gateway (1)')
    elsif secret and !signature
      # Signature missing when one expected (We have a secret but the Gateway doesn't)
      raise RuntimeError.new('Incorrectly signed response from Payment Gateway (2)');
    elsif secret and ourSignature != signature
      # Signature mismatch
      raise RuntimeError.new('Incorrectly signed response from Payment Gateway');
    end

    return true
  end

  # Collect browser device information.
  #
  # The method will return a self submitting HTML form designed to provided
  # the browser device details in the following integration fields;
  #   + 'deviceChannel'      - Fixed value 'browser',
  #   + 'deviceIdentity'      - Browser's UserAgent string
  #   + 'deviceTimeZone'      - Browser's timezone
  #   + 'deviceCapabilities'    - Browser's capabilities
  #   + 'deviceScreenResolution'  - Browser's screen resolution (widthxheightxcolour-depth)
  #   + 'deviceAcceptContent'  - Browser's accepted content types
  #   + 'deviceAcceptEncoding'  - Browser's accepted encoding methods
  #   + 'deviceAcceptLanguage'  - Browser's accepted languages
  #   + 'deviceAcceptCharset'  - Browser's accepted character sets
  #
  # The above fields will be submitted as child elements of a 'browserInfo'
  # parent field.
  #
  # The method accepts the following options;
  #   + 'formAttrs'    - HTML form attributes string
  #   + 'formData'    - associative array of additional post data
  #
  #
  # The method returns the HTML fragment that needs including in order to
  # render the HTML form.
  #
  # The browser must suport JavaScript in order to obtain the details and
  # submit the form.
  #
  # options (or nil)
  # @return  string        request HTML form.
  #
  def collectBrowserInfo(options = {})

    http_user_agent = @@coder.encode(@env["HTTP_USER_AGENT"])
    http_accept = @@coder.encode(@env["HTTP_ACCEPT"])
    http_accept_encoding = @@coder.encode(@env["HTTP_ACCEPT_ENCODING"])
    http_accept_language = @@coder.encode(@env["HTTP_ACCEPT_LANGUAGE"])

    formAttrs = ""
    if options.key?('formAttrs')
      formAttrs = options['formAttrs']
    end

    formFields = ""
    if options.key?('formData')
      options['formData'].each{|k,v|
        formFields << fieldToHtml(k, v)
      }
    end

    return (<<~INFOFORM)


<form id="collectBrowserInfo" method="post" action="?" #{formAttrs}>
<input type="hidden" name="browserInfo[deviceChannel]" value="browser" />
<input type="hidden" name="browserInfo[deviceIdentity]" value="#{http_user_agent}" />
<input type="hidden" name="browserInfo[deviceTimeZone]" value="0" />
<input type="hidden" name="browserInfo[deviceCapabilities]" value="" />
<input type="hidden" name="browserInfo[deviceScreenResolution]" value="1x1x1" />
<input type="hidden" name="browserInfo[deviceAcceptContent]" value="#{http_accept}" />
<input type="hidden" name="browserInfo[deviceAcceptEncoding]" value="#{http_accept_encoding}" />
<input type="hidden" name="browserInfo[deviceAcceptLanguage]" value="#{http_accept_language}" />
#{formFields}
</form>
<script>
  var screen_width = (window && window.screen ? window.screen.width : '0');
  var screen_height = (window && window.screen ? window.screen.height : '0');
  var screen_depths = [1, 4, 8, 15, 16, 24, 32, 48];
  var screen_depth = (window && window.screen && window.screen.colorDepth && screen_depths.indexOf(window.screen.colorDepth) >= 0 ? window.screen.colorDepth : '0');
  var identity = (window && window.navigator ? window.navigator.userAgent : '');
  var language = (window && window.navigator ? (window.navigator.language ? window.navigator.language : window.navigator.browserLanguage) : '');
  var timezone = (new Date()).getTimezoneOffset();
  var java = (window && window.navigator ? navigator.javaEnabled() : false);
  var fields = document.forms.collectBrowserInfo.elements;
  fields['browserInfo[deviceIdentity]'].value = identity;
  fields['browserInfo[deviceTimeZone]'].value = timezone;
  fields['browserInfo[deviceCapabilities]'].value = 'javascript' + (java ? ',java' : '');
  fields['browserInfo[deviceAcceptLanguage]'].value = language;
  fields['browserInfo[deviceScreenResolution]'].value = screen_width + 'x' + screen_height + 'x' + screen_depth;
  window.setTimeout('document.forms.collectBrowserInfo.submit()', 0);
</script>
INFOFORM
  end


  def fieldToHtml(name, value)
    ret = ""
    if value.is_a? Hash
      value.each { |k, v|
        ret << fieldToHtml(name + "[" + k + "]", v)
      }
      return ret
    else
      value = @@coder.encode(value)
      return "<input type=\"hidden\" name=\"#{name}\" value=\"#{value}\" />\n"
    end
  end

  
  def restructureArray(inAry)
    rtn = []

    inAry.each do |key, value|
        if (key.include?('[') && key.end_with?(']'))
            nestedKey, nestedValue = key[..key.length - 2].split('[', 2)
            nestedArray = rtn.assoc(nestedKey)

            if !nestedArray
                nestedArray = []
                nestedArray.push([nestedValue, value])
                rtn.push([nestedKey, nestedArray])
            else
                nestedArray[1].push([nestedValue, value])
            end
        else
            rtn.push([key, value])
        end
    end
    return rtn
end

  def flattenArray(inAry)
    rtn = []

    inAry.each  { |key, value|
      if value.is_a?(Array)
        value.each { |nestedKey, nestedValue|
          rtn.push([key + '[' + nestedKey + ']', nestedValue])
        }
      else
        rtn.push([key, value])
      end
    }
    
  return rtn
  end

  def convertToStringHashes(inputHash)
    rtn = {}
    inputHash.each do |key, value|
        if (key.include?('[') && key.end_with?(']'))
            nestedKey, nestedValue = key[..key.length - 2].split('[', 2)
            nestedArray = rtn.fetch(nestedKey, {})
            nestedArray[nestedValue] = value
            rtn[nestedKey] = nestedArray
        else
            rtn[key] = value
        end
    end

    return rtn
  end

  def http_build_query(object)
    h = hashify(object)
    result = ""
    separator = '&'
    h.keys.each do |key|
      result << (CGI.escape(key) + '=' + CGI.escape(h[key]) + separator)
    end
    result = result.sub(/#{separator}$/, '') # Remove the trailing k-v separator
    return result
  end


  def hashify(object, parent_key = '')
    raise ArgumentError.new('This is made for serializing Hashes and Arrays only') unless (object.is_a?(Hash) or object.is_a?(Array) or parent_key.length > 0)

    result = {}
    case object
    when String, Symbol, Numeric
      result[parent_key] = object.to_s
    when Hash
      # Recursively call hashify, building closure-like state by
      # appending the current location in the tree as new "parent_key"
      # values.
      hashes = object.map do |key, value|
        if parent_key =~ /^[0-9]+/ or parent_key.length == 0
          new_parent_key = key.to_s
        else
          new_parent_key = parent_key + '[' + key.to_s + ']'
        end
        hashify(value, new_parent_key)
      end
      hash = hashes.reduce { |memo, hash| memo.merge hash }
      result.merge! hash
    when Enumerable
      # _Very_ similar to above, but iterating with "each_with_index"
      hashes = {}
      object.each_with_index do |value, index|
        if parent_key.length == 0
          new_parent_key = index.to_s
        else
          new_parent_key = parent_key + '[' + index.to_s + ']'
        end
        hashes.merge! hashify(value, new_parent_key)
      end
      result.merge! hashes
    else
      raise Exception.new("This should only be serializing Strings, Symbols, or Numerics.")
    end

    return result
  end


end
