# frozen_string_literal: true

module Volcano
  # Authentication operations for the internal generated transport.
  class GeneratedTransport
    MALFORMED_USER_PROFILE = 'Expected a complete user profile'
    private_constant :MALFORMED_USER_PROFILE

    def auth_signup(authorization:, email:, password:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthSignupRequest.new(
          email: email,
          password: password,
          user_metadata: metadata
        )
        response(*apis.authentication.auth_signup_with_http_info(request))
      end
    end

    def auth_signin(authorization:, email:, password:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.authentication.auth_signin_with_http_info(
          Generated::AuthSigninRequest.new(email: email, password: password)
        )
        response(data, status, headers)
      end
    end

    def auth_get_user(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        response(
          *apis.authentication.auth_get_user_with_http_info(debug_return_type: 'Object')
        )
      end
    rescue ArgumentError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end

    def auth_refresh(authorization:, refresh_token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRefreshRequest.new(refresh_token: refresh_token)
        response(*apis.authentication.auth_refresh_with_http_info(auth_refresh_request: request))
      end
    end

    def auth_logout(authorization:, refresh_token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRefreshRequest.new(refresh_token: refresh_token)
        response(*apis.authentication.auth_logout_with_http_info(auth_refresh_request: request))
      end
    end
  end
end
