# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeAuthenticationApi
      include FakeEmailChangeApi

      attr_accessor :email_change_body
      attr_reader :anonymous_conversion_calls, :anonymous_signup_calls, :calls, :confirm_email_calls,
                  :email_change_calls,
                  :forgot_password_calls, :get_user_calls,
                  :logout_calls, :refresh_calls,
                  :resend_confirmation_calls,
                  :reset_password_calls, :signup_calls, :update_user_calls

      def initialize
        @calls = []
        @confirm_email_calls = []
        @forgot_password_calls = []
        @get_user_calls = []
        @logout_calls = []
        @refresh_calls = []
        @resend_confirmation_calls = []
        @reset_password_calls = []
        @signup_calls = []
        @update_user_calls = []
      end

      def auth_signin_with_http_info(body)
        @calls << body
        [FakeGeneratedModel.new(access_token: 'token'), 200, { 'request-id' => 'auth' }]
      end

      def auth_signup_anonymous_with_http_info(options = {})
        (@anonymous_signup_calls ||= []) << options
        session = {
          access_token: 'anonymous-access',
          refresh_token: 'anonymous-refresh',
          user: { id: 'anonymous-user' }
        }
        [FakeGeneratedModel.new(session), 201, {}]
      end

      def auth_convert_anonymous_with_http_info(body, options = {})
        (@anonymous_conversion_calls ||= []) << [body, options]
        profile = {
          user: {
            id: 'anonymous-user', email: 'converted@example.com', status: 'active',
            created_at: '2026-09-01T12:00:00Z'
          }
        }
        [JSON.generate(profile), 200, {}]
      end

      def auth_request_email_change_with_http_info(body, options = {})
        (@email_change_calls ||= []) << [body, options]
        [@email_change_body || JSON.generate({}), 200, {}]
      end

      def auth_confirm_email_with_http_info(body, options = {})
        @confirm_email_calls << [body, options]
        [FakeGeneratedModel.new(message: 'Email confirmed successfully'), 200, {}]
      end

      def auth_resend_confirmation_with_http_info(body, options = {})
        @resend_confirmation_calls << [body, options]
        [FakeGeneratedModel.new(message: 'Confirmation sent'), 200, {}]
      end

      def auth_get_user_with_http_info(options = {})
        @get_user_calls << options
        profile = {
          user: {
            id: 'user-123', email: 'user@example.com', status: 'active',
            user_metadata: { display_name: 'Ada' }
          }
        }
        [JSON.generate(profile), 200, { 'request-id' => 'user' }]
      end

      def auth_signup_with_http_info(body)
        @signup_calls << body
        acknowledgement = {
          confirmation_required: true,
          message: 'Check your email to confirm your account'
        }
        [FakeGeneratedModel.new(acknowledgement), 201, { 'request-id' => 'signup' }]
      end

      def auth_forgot_password_with_http_info(body, options = {})
        @forgot_password_calls << [body, options]
        acknowledgement = { message: 'If the email exists, a password reset link has been sent.' }
        [FakeGeneratedModel.new(acknowledgement), 200, { 'request-id' => 'forgot-password' }]
      end

      def auth_reset_password_with_http_info(body, options = {})
        @reset_password_calls << [body, options]
        [FakeGeneratedModel.new(message: 'Password reset successful'), 200, {}]
      end

      def auth_update_user_with_http_info(options)
        @update_user_calls << options
        profile = {
          user: {
            id: 'user-123', email: 'user@example.com', status: 'active',
            user_metadata: { display_name: 'Grace' }, created_at: '2026-08-31T12:00:00Z'
          }
        }
        [JSON.generate(profile), 200, { 'request-id' => 'update-user' }]
      end

      def auth_refresh_with_http_info(options)
        @refresh_calls << options
        [FakeGeneratedModel.new(access_token: 'refreshed-token'), 200, { 'request-id' => 'refresh' }]
      end

      def auth_logout_with_http_info(options)
        @logout_calls << options
        [nil, 204, { 'request-id' => 'logout' }]
      end
    end
  end
end
