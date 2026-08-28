# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Invokes auth transports with retry and credential redaction.
  module AuthInvocation
    private

    def anonymous_body(operation, expected_status, secrets: [], **arguments)
      securely(*secrets) do
        response = transport_response(operation, authorization: @client.anon_token, **arguments)
        Transport.body(response, expected_status)
      end
    end

    def authenticated_body(operation, expected_status, secrets: [], **arguments)
      securely(*auth_credentials, *secrets) do
        response = authenticated_response(operation, **arguments)
        response = retry_authenticated(operation, **arguments) if refreshable_unauthorized?(response)
        Transport.body(response, expected_status)
      end
    end

    def authenticated_response(operation, **arguments)
      transport_response(operation, authorization: @client.session_token, **arguments)
    end

    def retry_authenticated(operation, **arguments)
      refresh_session
      authenticated_response(operation, **arguments)
    end

    def refreshable_unauthorized?(response)
      response.status == 401 && @client.current_session&.refresh_token
    end

    def auth_credentials
      session = @client.current_session
      [session&.access_token, session&.refresh_token]
    end

    def transport_response(operation, **arguments)
      Transport.invoke { @transport.public_send(operation, **arguments) }
    end

    def securely(*secrets)
      yield
    rescue StandardError => e
      raise Redaction.exception(e, secrets: secrets), cause: e.cause
    end

    def auth_response_error(message = 'Invalid authentication response')
      Error::AuthenticationError.new(message)
    end
  end
  private_constant :AuthInvocation
end
