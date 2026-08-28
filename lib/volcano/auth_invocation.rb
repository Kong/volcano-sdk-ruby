# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Invokes auth transports with retry and credential redaction.
  module AuthInvocation
    private

    def anonymous_body(operation, expected_status, secrets: [], **arguments)
      securely(@client.anon_token, *secrets) do
        response = transport_response(operation, authorization: @client.anon_token, **arguments)
        Transport.body(response, expected_status)
      end
    end

    def authenticated_body(operation, expected_status, secrets: [], retry_unauthorized: true, **arguments)
      synchronize_auth_operation do
        rejected_session = @client.current_session
        response, response_credentials = authenticated_attempt(operation, secrets:, **arguments)
        if retry_unauthorized && refreshable_unauthorized?(response)
          response, response_credentials = retry_authenticated(
            operation, rejected_session:, secrets:, **arguments
          )
        end
        invalidate_unauthorized(response, rejected_session) if retry_unauthorized
        securely(*response_credentials, *secrets) { Transport.body(response, expected_status) }
      end
    end

    def authenticated_response(operation, **arguments)
      transport_response(operation, authorization: @client.session_token, **arguments)
    end

    def retry_authenticated(operation, rejected_session:, secrets:, **arguments)
      refresh_session_for(rejected_session)
      authenticated_attempt(operation, secrets:, **arguments)
    end

    def authenticated_attempt(operation, secrets:, **arguments)
      credentials = auth_credentials
      response = securely(*credentials, *secrets) do
        authenticated_response(operation, **arguments)
      end
      [response, credentials]
    end

    def refreshable_unauthorized?(response)
      response.status == 401 && @client.current_session&.refresh_token
    end

    def invalidate_unauthorized(response, rejected_session)
      return unless response.status == 401
      return unless rejected_session
      return unless rejected_session.refresh_token || @client.current_session.equal?(rejected_session)

      @client.clear_auth
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
