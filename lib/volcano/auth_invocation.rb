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
      rejected_session = @client.current_session
      response = securely(*auth_credentials, *secrets) do
        authenticated_response(operation, **arguments)
      end
      if refreshable_unauthorized?(response)
        response = retry_authenticated(
          operation, rejected_session:, secrets:, **arguments
        )
      end
      securely(*auth_credentials, *secrets) { Transport.body(response, expected_status) }
    end

    def authenticated_response(operation, **arguments)
      transport_response(operation, authorization: @client.session_token, **arguments)
    end

    def retry_authenticated(operation, rejected_session:, secrets:, **arguments)
      refresh_session_for(rejected_session)
      securely(*auth_credentials, *secrets) do
        authenticated_response(operation, **arguments)
      end
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
      raise Redaction.exception(e, secrets: secrets), cause: nil
    end

    def auth_response_error(message = 'Invalid authentication response')
      Error::AuthenticationError.new(message)
    end
  end
  private_constant :AuthInvocation
end
