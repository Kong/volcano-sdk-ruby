# frozen_string_literal: true

module Volcano
  # Email-change request behavior for the authentication facade.
  class Auth
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
      values = payload.is_a?(Hash) ? payload : {}
      EmailChangeResult.new(message: values['message'], new_email: values['new_email'])
    end
  end
end
