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

    def auth_forgot_password(authorization:, email:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthForgotPasswordRequest.new(email: email)
        response(*apis.authentication.auth_forgot_password_with_http_info(request))
      end
    end

    def auth_get_user(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        body, status, headers = apis.authentication.auth_get_user_with_http_info(
          debug_return_type: 'String'
        )
        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end

    def auth_update_user(authorization:, password:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        body, status, headers = apis.authentication.auth_update_user_with_http_info(
          **update_user_options(password:, metadata:)
        )
        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
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

    private

    def update_user_options(password:, metadata:)
      attributes = {}
      attributes[:password] = password unless password.nil?
      attributes[:user_metadata] = metadata unless metadata.nil?
      {
        auth_update_user_request: Generated::AuthUpdateUserRequest.new(attributes),
        debug_body: attributes,
        debug_return_type: 'String'
      }
    end
  end
end
