# frozen_string_literal: true

# Public namespace for Volcano SDK transport adapters.
module Volcano
  # Generated authentication operations exposed through the stable transport.
  module GeneratedAuthenticationTransport
    def auth_get_password_policy(authorization:)
      auth_call(authorization, :auth_get_password_policy_with_http_info)
    end

    def auth_signin(authorization:, email:, password:)
      body = generated_model(:AuthSigninRequest, email:, password:)
      auth_call(authorization, :auth_signin_with_http_info, body)
    end

    def auth_signup(authorization:, email:, password:, user_metadata: nil)
      body = generated_model(:AuthSignupRequest, email:, password:, user_metadata:)
      auth_call(authorization, :auth_signup_with_http_info, body)
    end

    def auth_refresh(authorization:, refresh_token:)
      body = generated_model(:AuthRefreshRequest, refresh_token:)
      auth_call(authorization, :auth_refresh_with_http_info, auth_refresh_request: body)
    end

    def auth_logout(authorization:, refresh_token:)
      body = generated_model(:AuthRefreshRequest, refresh_token:)
      auth_call(authorization, :auth_logout_with_http_info, auth_refresh_request: body)
    end

    def auth_get_user(authorization:)
      auth_call(authorization, :auth_get_user_with_http_info)
    end

    def auth_update_user(authorization:, password: nil, user_metadata: nil)
      body = generated_model(:AuthUpdateUserRequest, password:, user_metadata:)
      auth_call(authorization, :auth_update_user_with_http_info, auth_update_user_request: body)
    end

    def auth_signup_anonymous(authorization:, user_metadata: nil)
      body = generated_model(:AuthSignupAnonymousRequest, user_metadata:)
      auth_call(authorization, :auth_signup_anonymous_with_http_info, auth_signup_anonymous_request: body)
    end

    def auth_convert_anonymous(authorization:, **attributes)
      body = generated_model(:AuthSignupRequest, **attributes)
      auth_call(authorization, :auth_convert_anonymous_with_http_info, body)
    end

    def auth_confirm_email(authorization:, token:)
      body = generated_model(:AuthConfirmEmailRequest, token:)
      auth_call(authorization, :auth_confirm_email_with_http_info, body)
    end

    def auth_resend_confirmation(authorization:, email:)
      body = generated_model(:AuthForgotPasswordRequest, email:)
      auth_call(authorization, :auth_resend_confirmation_with_http_info, body)
    end

    def auth_forgot_password(authorization:, email:)
      body = generated_model(:AuthForgotPasswordRequest, email:)
      auth_call(authorization, :auth_forgot_password_with_http_info, body)
    end

    def auth_reset_password(authorization:, token:, new_password:)
      body = generated_model(:AuthResetPasswordRequest, token:, new_password:)
      auth_call(authorization, :auth_reset_password_with_http_info, body)
    end

    def auth_request_email_change(authorization:, new_email:)
      body = generated_model(:AuthRequestEmailChangeRequest, new_email:)
      auth_call(authorization, :auth_request_email_change_with_http_info, body)
    end

    def auth_confirm_email_change(authorization:, email_change_token:)
      body = generated_model(:AuthConfirmEmailChangeRequest, email_change_token:)
      auth_call(authorization, :auth_confirm_email_change_with_http_info, body)
    end

    def auth_cancel_email_change(authorization:)
      auth_call(authorization, :auth_cancel_email_change_with_http_info)
    end

    def auth_get_my_sessions(authorization:, **)
      auth_call(authorization, :auth_get_my_sessions_with_http_info, **)
    end

    def auth_delete_my_session(authorization:, session_id:)
      auth_call(authorization, :auth_delete_my_session_with_http_info, session_id)
    end

    def auth_delete_all_my_sessions(authorization:)
      auth_call(authorization, :auth_delete_all_my_sessions_with_http_info)
    end

    def auth_list_identities(authorization:)
      auth_call(authorization, :auth_list_identities_with_http_info)
    end

    def auth_unlink_identity(authorization:, identity_id:)
      auth_call(authorization, :auth_unlink_identity_with_http_info, identity_id)
    end

    def auth_list_methods(authorization:)
      auth_call(authorization, :auth_list_methods_with_http_info)
    end

    def auth_promote_method(authorization:, method_id:)
      auth_call(authorization, :auth_promote_method_with_http_info, method_id)
    end
  end

  # Generated OAuth operations exposed through the stable transport.
  module GeneratedOAuthTransport
    DEVICE_GRANT_TYPE = 'urn:ietf:params:oauth:grant-type:device_code'

    def auth_device_authorize(authorization:, client_id:)
      body = generated_model(:AuthDeviceAuthorizeRequest, client_id:)
      oauth_call(authorization, :auth_device_authorize_with_http_info, body)
    end

    def auth_device_token(authorization:, client_id:, device_code:)
      body = generated_model(
        :AuthDeviceTokenRequest, grant_type: DEVICE_GRANT_TYPE, client_id:, device_code:
      )
      oauth_call(authorization, :auth_device_token_with_http_info, body)
    end

    def auth_device_verify(authorization:, user_code:, action:)
      body = generated_model(:AuthDeviceVerifyRequest, user_code:, action:)
      oauth_call(authorization, :auth_device_verify_with_http_info, body)
    end

    def auth_platform_exchange(authorization:, client_id:)
      body = generated_model(:AuthPlatformExchangeRequest, client_id:)
      oauth_call(authorization, :auth_platform_exchange_with_http_info, body)
    end

    def auth_oauth_authorize(authorization:, provider:, redirect_url:, state:)
      options = {
        redirect_url:, client_state: state, response_mode: 'code', follow_location: false
      }
      oauth_call(authorization, :auth_o_auth_authorize_with_http_info, provider, authorization, options)
    end

    def auth_oauth_exchange(authorization:, code:, redirect_url:)
      body = generated_model(:AuthOAuthExchangeRequest, code:, redirect_url:)
      oauth_call(authorization, :auth_o_auth_exchange_with_http_info, body)
    end

    def auth_link_oauth_provider(authorization:, provider:, redirect_url:, state:)
      options = { redirect_url:, client_state: state, response_mode: 'code' }
      oauth_call(authorization, :auth_link_o_auth_provider_with_http_info, provider, options)
    end

    def auth_unlink_oauth_provider(authorization:, provider:)
      oauth_call(authorization, :auth_unlink_o_auth_provider_with_http_info, provider)
    end

    def auth_list_oauth_providers(authorization:)
      oauth_call(authorization, :auth_list_o_auth_providers_with_http_info)
    end

    def refresh_oauth_provider_token(authorization:, provider:)
      oauth_call(authorization, :refresh_o_auth_provider_token_with_http_info, provider)
    end

    def get_oauth_provider_token(authorization:, provider:)
      oauth_call(authorization, :get_o_auth_provider_token_with_http_info, provider)
    end

    def call_oauth_provider_api(authorization:, provider:, **attributes)
      body = generated_model(:CallOAuthProviderAPIRequest, **attributes)
      oauth_call(
        authorization, :call_o_auth_provider_api_with_http_info, provider, body,
        debug_return_type: 'Object'
      )
    end
  end

  # Shared invocation helpers for generated authentication transports.
  module GeneratedAuthInvocation
    private

    def generated_model(name, **attributes)
      Generated.const_get(name).new(attributes.compact)
    end

    def auth_call(authorization, operation, *, **)
      generated_call(authorization, :authentication, operation, *, **)
    end

    def oauth_call(authorization, operation, *)
      generated_call(authorization, :oauth, operation, *)
    end

    def generated_call(authorization, api_name, operation, *arguments, **options)
      invoke do
        api = @api_factory.call(authorization).public_send(api_name)
        arguments << options unless options.empty?
        data, status, headers = api.public_send(operation, *arguments)
        response(data, status, headers)
      end
    end
  end

  private_constant :GeneratedAuthenticationTransport, :GeneratedOAuthTransport,
                   :GeneratedAuthInvocation
end
