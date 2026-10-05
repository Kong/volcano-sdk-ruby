# frozen_string_literal: true

module Volcano
  # Email-change request behavior for the authentication facade.
  module AuthEmailChange
    INVALID_EMAIL_CHANGE_RESULT = 'Expected a valid email-change acknowledgement'
    private_constant :INVALID_EMAIL_CHANGE_RESULT

    def request_email_change(new_email:)
      session_payload(200, decode: :email_change_result) do
        request_email = new_email.dup.freeze
        ->(token) { email_change_response(token, request_email) }
      end
    end

    def cancel_email_change
      session_payload(200) { ->(token) { cancel_email_change_response(token) } }
      nil
    end

    def confirm_email_change(token:)
      profile_request do
        request_token = token.dup.freeze
        ->(access_token) { confirm_email_change_response(access_token, request_token) }
      end
    end

    private

    def email_change_response(access_token, new_email)
      Transport.invoke do
        @transport.auth_request_email_change(authorization: access_token, new_email:)
      end
    end

    def cancel_email_change_response(access_token)
      Transport.invoke do
        @transport.auth_cancel_email_change(authorization: access_token)
      end
    end

    def confirm_email_change_response(access_token, token)
      Transport.invoke do
        @transport.auth_confirm_email_change(authorization: access_token, token:)
      end
    end

    def email_change_result(payload)
      raise TypeError, INVALID_EMAIL_CHANGE_RESULT unless payload.is_a?(Hash)

      message = payload['message']
      new_email = payload['new_email']
      unless [message, new_email].all? { |value| value.nil? || value.is_a?(String) }
        raise TypeError, INVALID_EMAIL_CHANGE_RESULT
      end

      EmailChangeResult.new(message: owned_string(message), new_email: owned_string(new_email))
    end

    def owned_string(value)
      value&.dup&.freeze
    end
  end
end
