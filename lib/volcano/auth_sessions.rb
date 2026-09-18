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
      body = session_payload(200) { ->(token) { list_sessions_response(token, page, limit) } }
      session_page(body)
    end

    def delete_all_other_sessions
      session_payload(204) { ->(token) { delete_all_other_sessions_response(token) } }
      nil
    end

    def delete_session(session_id)
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      request_id = session_id.dup.freeze
      deletes_current = same_session_id?(binding.last.access_token, request_id)
      error = delete_bound_session_error(binding, request_id)
      current_unchanged = session_unchanged_after_deletion?(deletes_current, error, binding)
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

    def delete_bound_session_error(binding, session_id)
      response = session_request(binding: binding) { |token| delete_session_response(token, session_id) }
      Transport.body(response, 204)
      nil
    rescue Error::VolcanoError => e
      e
    end

    def session_unchanged_after_deletion?(deletes_current, error, binding)
      uncertain = error.nil? || error.is_a?(Error::TransportError)
      return @client.clear_session_if_current?(binding.first, lineage: binding[1]) if deletes_current && uncertain

      active = @client.capture_session_binding
      active[1] == binding[1] || rejected_refresh?(binding, active)
    end

    def same_session_id?(access_token, session_id)
      current_session_id = access_token_session_id(access_token)
      session_id.is_a?(String) && current_session_id&.casecmp?(session_id)
    end

    def access_token_session_id(access_token)
      SessionCredentials.session_id(access_token)
    end
  end
end
