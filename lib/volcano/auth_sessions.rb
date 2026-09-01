# frozen_string_literal: true

module Volcano
  # Multi-device session behavior for the authentication facade.
  class Auth
    def delete_all_other_sessions
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      Transport.body(delete_all_other_sessions_response(current.access_token), 204)
      raise Error::SessionChangedError unless @client.capture_session.first == generation
    end

    def delete_session(session_id)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      Transport.body(delete_session_response(current.access_token, session_id), 204)
      raise Error::SessionChangedError unless @client.capture_session.first == generation
    end

    private

    def delete_all_other_sessions_response(access_token)
      Transport.invoke do
        @transport.auth_delete_all_my_sessions(authorization: access_token)
      end
    end

    def delete_session_response(access_token, session_id)
      Transport.invoke do
        @transport.auth_delete_my_session(
          authorization: access_token,
          session_id: session_id
        )
      end
    end
  end
end
