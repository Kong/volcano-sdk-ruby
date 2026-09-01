# frozen_string_literal: true

require 'base64'
require 'json'

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

      deletes_current = access_token_session_id(current.access_token) == session_id
      Transport.body(delete_session_response(current.access_token, session_id), 204)
      current_unchanged = if deletes_current
                            @client.clear_session_if_current(generation)
                          else
                            @client.capture_session.first == generation
                          end
      raise Error::SessionChangedError unless current_unchanged
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

    def access_token_session_id(access_token)
      parts = access_token.split('.')
      return unless parts.length == 3

      padding = '=' * (-parts.fetch(1).length % 4)
      payload = JSON.parse(Base64.urlsafe_decode64(parts.fetch(1) + padding))
      session_id = payload['session_id']
      session_id if session_id.is_a?(String) && !session_id.empty?
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end
end
