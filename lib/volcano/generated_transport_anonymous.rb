# frozen_string_literal: true

module Volcano
  # Anonymous authentication operations for the internal generated transport.
  class GeneratedTransport
    def auth_signup_anonymous(authorization:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthSignupAnonymousRequest.new(user_metadata: metadata)
        data, status, headers = apis.authentication.auth_signup_anonymous_with_http_info(
          auth_signup_anonymous_request: request
        )
        response(data, status, headers)
      end
    end

    def auth_convert_anonymous(authorization:, email:, password:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        attributes = { email:, password:, user_metadata: metadata }
        request = Generated::AuthSignupRequest.new(email:, password:, user_metadata: metadata)
        body, status, headers = apis.authentication.auth_convert_anonymous_with_http_info(
          request,
          debug_body: attributes,
          debug_return_type: 'String'
        )
        raise TypeError unless body.is_a?(String)

        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end
  end
end
