# frozen_string_literal: true

require 'json'

module Volcano
  # Maps the internal wire response to immutable public session values.
  module SessionPageMapping
    SESSION_FIELDS = %i[
      id user_id provider expires_at is_active is_current user_agent ip_address last_ip_address
      last_activity_at session_started_at created_at updated_at
    ].freeze
    REQUIRED_SESSION_FIELDS = SESSION_FIELDS.first(6).freeze

    private

    def session_page(body)
      raise TypeError, 'Expected a complete session page' unless body.is_a?(Hash)

      sessions = body.fetch('sessions')
      raise TypeError, 'Expected a complete session page' unless sessions.is_a?(Array)

      SessionPage.new(
        sessions: sessions.map { |attributes| auth_session(attributes) },
        total: body.fetch('total'), page: body.fetch('page'), limit: body.fetch('limit'),
        total_pages: body.fetch('total_pages')
      )
    rescue KeyError
      raise TypeError, 'Expected a complete session page'
    end

    def auth_session(attributes)
      raise TypeError, 'Expected a complete authentication session' unless attributes.is_a?(Hash)

      required = REQUIRED_SESSION_FIELDS.to_h { |name| [name, attributes.fetch(name.to_s)] }
      optional = (SESSION_FIELDS - REQUIRED_SESSION_FIELDS).to_h do |name|
        [name, attributes[name.to_s]]
      end
      AuthSession.new(**required, **optional)
    rescue KeyError
      raise TypeError, 'Expected a complete authentication session'
    end
  end
  private_constant :SessionPageMapping

  # Multi-device session behavior for the authentication facade.
  class Auth
    include SessionPageMapping

    def list_sessions(page: 1, limit: 20)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      body = Transport.body(list_sessions_response(current.access_token, page, limit), 200)
      result = session_page(body)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    def delete_all_other_sessions
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      Transport.body(delete_all_other_sessions_response(current.access_token), 204)
      raise Error::SessionChangedError unless @client.capture_session.first == generation
    end

    def delete_session(session_id)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      deletes_current = same_session_id?(current.access_token, session_id)
      error = delete_session_error(current.access_token, session_id)
      current_unchanged = session_unchanged_after_deletion?(deletes_current, error, generation)
      raise Error::SessionChangedError, cause: error unless current_unchanged

      raise error if error
    end

    private

    def list_sessions_response(access_token, page, limit)
      Transport.invoke do
        @transport.auth_get_my_sessions(
          authorization: access_token,
          page: page,
          limit: limit
        )
      end
    end

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

    def delete_session_error(access_token, session_id)
      Transport.body(delete_session_response(access_token, session_id), 204)
      nil
    rescue Error::VolcanoError => e
      e
    end

    def session_unchanged_after_deletion?(deletes_current, error, generation)
      uncertain = error.nil? || error.is_a?(Error::TransportError)
      return @client.clear_session_if_current?(generation) if deletes_current && uncertain

      @client.capture_session.first == generation
    end

    def same_session_id?(access_token, session_id)
      current_session_id = access_token_session_id(access_token)
      session_id.is_a?(String) && current_session_id&.casecmp?(session_id)
    end

    def access_token_session_id(access_token)
      parts = access_token.split('.')
      return unless parts.length == 3

      encoded = parts.fetch(1).tr('-_', '+/')
      padding = '=' * (-encoded.length % 4)
      payload = JSON.parse((encoded + padding).unpack1('m0'))
      session_id = payload['session_id']
      session_id if session_id.is_a?(String) && !session_id.empty?
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end
end
