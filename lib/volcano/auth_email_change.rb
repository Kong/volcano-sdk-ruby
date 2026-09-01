# frozen_string_literal: true

module Volcano
  # Email-change request behavior for the authentication facade.
  class Auth
    INVALID_EMAIL_CHANGE_RESULT = 'Expected a valid email-change acknowledgement'
    private_constant :INVALID_EMAIL_CHANGE_RESULT

    def request_email_change(new_email:)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      payload = Transport.body(email_change_response(current.access_token, new_email), 200)
      result = email_change_result(payload)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    private

    def email_change_response(access_token, new_email)
      Transport.invoke do
        @transport.auth_request_email_change(authorization: access_token, new_email:)
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
