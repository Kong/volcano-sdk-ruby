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
        data, status, headers = apis.authentication.auth_signup_with_http_info(request)
        response(data, status, headers)
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
        data, status, headers = apis.authentication.auth_forgot_password_with_http_info(
          request, debug_return_type: 'String'
        )
        response(data, status, headers)
      end
    end

    def auth_reset_password(authorization:, token:, new_password:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthResetPasswordRequest.new(token:, new_password:)
        data, status, headers = apis.authentication.auth_reset_password_with_http_info(
          request, debug_return_type: 'String'
        )
        response(data, status, headers)
      end
    end

    def auth_get_user(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        body, status, headers = apis.authentication.auth_get_user_with_http_info(
          debug_return_type: 'String'
        )
        raise TypeError unless body.is_a?(String)

        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end

    def auth_update_user(authorization:, password:, metadata:)
      invoke do
        apis = @api_factory.call(authorization)
        options = update_user_options(password:, metadata:)
        body, status, headers = apis.authentication.auth_update_user_with_http_info(options)
        raise TypeError unless body.is_a?(String)

        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end

    def auth_refresh(authorization:, refresh_token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRefreshRequest.new(refresh_token: refresh_token)
        data, status, headers = apis.authentication.auth_refresh_with_http_info(auth_refresh_request: request)
        response(data, status, headers)
      end
    end

    def auth_logout(authorization:, refresh_token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRefreshRequest.new(refresh_token: refresh_token)
        data, status, headers = apis.authentication.auth_logout_with_http_info(auth_refresh_request: request)
        response(data, status, headers)
      end
    end

    private

    def update_user_options(password:, metadata:)
      attributes = { password: password, user_metadata: metadata }.compact
      {
        auth_update_user_request: Generated::AuthUpdateUserRequest.new(attributes),
        debug_body: attributes,
        debug_return_type: 'String'
      }
    end
  end
end
