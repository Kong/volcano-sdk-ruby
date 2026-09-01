# frozen_string_literal: true

module Volcano
  # Password-reset request behavior for the authentication facade.
  class Auth
    INVALID_PASSWORD_RESET_RESULT = 'Expected a complete password reset acknowledgement'
    private_constant :INVALID_PASSWORD_RESET_RESULT

    def reset_password_for_email(email:)
      payload = Transport.body(reset_password_for_email_response(email:), 200)
      message = payload['message'] if payload.is_a?(Hash)
      valid = message.is_a?(String) && !message.strip.empty?
      raise Error::AuthenticationError, INVALID_PASSWORD_RESET_RESULT unless valid

      message.dup.freeze
    end

    private

    def reset_password_for_email_response(email:)
      Transport.invoke do
        @transport.auth_forgot_password(authorization: @client.anon_token, email: email)
      end
    end
  end
end
