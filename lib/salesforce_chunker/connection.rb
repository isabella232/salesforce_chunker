require "httparty"

module SalesforceChunker
  class Connection

    def initialize(username: "", password: "", security_token: "", domain: "login", salesforce_version: "42.0", **options)
      @log = options[:logger] || Logger.new(options[:log_output])
      @log.progname = "salesforce_chunker"

      response = HTTParty.post(
        "https://#{domain}.salesforce.com/services/Soap/u/#{salesforce_version}",
        headers: { "SOAPAction": "login", "Content-Type": "text/xml; charset=UTF-8" },
        body: self.class.login_soap_request_body(username, password, security_token)
      ).parsed_response

      result = response["Envelope"]["Body"]["loginResponse"]["result"]

      instance = self.class.get_instance(result["serverUrl"])

      @base_url = "https://#{instance}.salesforce.com/services/async/#{salesforce_version}/"
      @default_headers = {
        "Content-Type": "application/json",
        "X-SFDC-Session": result["sessionId"],
        "Accept-Encoding": "gzip",
      }
    rescue NoMethodError
      raise ConnectionError, response["Envelope"]["Body"]["Fault"]["faultstring"]
    end

    def post_json(url, body, headers={})
      post(url, body.to_json, headers)
    end

    def post(url, body, headers={})
      @log.info "POST: #{url}"
      response = HTTParty.post(@base_url + url, headers: @default_headers.merge(headers), body: body)
      parsed_response = self.class.handle_response_parsing("post", url, response)
      self.class.check_response_error(parsed_response)
    end

    def get_json(url, headers={})
      @log.info "GET: #{url}"
      response = HTTParty.get(@base_url + url, headers: @default_headers.merge(headers))
      parsed_response = self.class.handle_response_parsing("get", url, response)
      self.class.check_response_error(parsed_response)
    end

    private

    def self.login_soap_request_body(username, password, security_token)
      "<?xml version=\"1.0\" encoding=\"utf-8\" ?>
      <env:Envelope
              xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"
              xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
              xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\"
              xmlns:urn=\"urn:partner.soap.sforce.com\">
          <env:Body>
              <n1:login xmlns:n1=\"urn:partner.soap.sforce.com\">
                  <n1:username>#{username.encode(xml: :text)}</n1:username>
                  <n1:password>#{password.encode(xml: :text)}#{security_token.encode(xml: :text)}</n1:password>
              </n1:login>
          </env:Body>
      </env:Envelope>"
    end

    def self.get_instance(server_url)
      /https:\/\/(.*).salesforce.com/.match(server_url)[1]
    end

    def self.handle_response_parsing(type, url, response)
      if response.content_type == "application/xml"
        SalesforceChunker::XMLToJSONPatch.apply(type, url, response.parsed_response)
      else
        response.parsed_response
      end
    end

    def self.check_response_error(response)
      if response.is_a?(Hash) && response.key?("exceptionCode")
        raise ResponseError, "#{response["exceptionCode"]}: #{response["exceptionMessage"]}"
      else
        response
      end
    end
  end
end
