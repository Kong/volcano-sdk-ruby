# frozen_string_literal: true

module Volcano
  # Maps the internal wire response to immutable public session values.
  module SessionPageMapping
    private

    def session_page(body)
      raise TypeError, 'Expected a complete session page' unless body.is_a?(Hash)

      sessions = body.fetch('sessions')
      raise TypeError, 'Expected a complete session page' unless sessions.is_a?(Array)

      SessionPage.new(
        sessions: sessions.map { |attributes| auth_session(attributes) },
        total: required_integer(body, 'total'), page: required_integer(body, 'page'),
        limit: required_integer(body, 'limit'), total_pages: required_integer(body, 'total_pages')
      )
    rescue KeyError
      raise TypeError, 'Expected a complete session page'
    end

    def auth_session(attributes)
      raise TypeError, 'Expected a complete authentication session' unless attributes.is_a?(Hash)

      build_auth_session(attributes)
    rescue KeyError
      raise TypeError, 'Expected a complete authentication session'
    end

    def build_auth_session(attributes)
      AuthSession.new(
        id: required_string(attributes, 'id'), user_id: required_string(attributes, 'user_id'),
        provider: required_string(attributes, 'provider'), expires_at: required_time(attributes, 'expires_at'),
        is_active: required_boolean(attributes, 'is_active'), is_current: required_boolean(attributes, 'is_current'),
        user_agent: optional_string(attributes, 'user_agent'), ip_address: optional_string(attributes, 'ip_address'),
        last_ip_address: optional_string(attributes, 'last_ip_address'),
        last_activity_at: optional_time(attributes, 'last_activity_at'),
        session_started_at: optional_time(attributes, 'session_started_at'),
        created_at: optional_time(attributes, 'created_at'), updated_at: optional_time(attributes, 'updated_at')
      )
    end

    def required_integer(body, name)
      value = body.fetch(name)
      raise TypeError, 'Expected a complete session page' unless value.is_a?(Integer)

      value
    end

    def required_string(body, name)
      value = body.fetch(name)
      raise TypeError, 'Expected a complete authentication session' unless value.is_a?(String)

      value
    end

    def required_time(body, name)
      value = body.fetch(name)
      raise TypeError, 'Expected a complete authentication session' unless value.is_a?(Time)

      value
    end

    def required_boolean(body, name)
      value = body.fetch(name)
      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        raise TypeError, 'Expected a complete authentication session'
      end

      value
    end

    def optional_string(body, name)
      value = body[name]
      raise TypeError, 'Expected a complete authentication session' unless value.nil? || value.is_a?(String)

      value
    end

    def optional_time(body, name)
      value = body[name]
      raise TypeError, 'Expected a complete authentication session' unless value.nil? || value.is_a?(Time)

      value
    end
  end
  private_constant :SessionPageMapping
end
