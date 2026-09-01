# frozen_string_literal: true

module Volcano
  # Anonymous authentication operations for the internal generated transport.
  class GeneratedTransport
    def auth_signup_anonymous(authorization:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthSignupAnonymousRequest.new(user_metadata: metadata)
        response(
          *apis.authentication.auth_signup_anonymous_with_http_info(
            auth_signup_anonymous_request: request
          )
        )
      end
    end
  end
end
