# frozen_string_literal: true

module Volcano
  # Builds and validates owned credential snapshots for the auth facade.
  module AuthSessionConstruction
    INCOMPLETE_SESSION = 'Expected a complete Volcano::Session'
    private_constant :INCOMPLETE_SESSION

    private

    def build_session(payload)
      raise TypeError, INCOMPLETE_SESSION unless payload.is_a?(Hash)

      user = payload.fetch('user')
      raise TypeError, INCOMPLETE_SESSION unless user.is_a?(Hash)

      owned_session(
        access_token: required_session_string(payload.fetch('access_token')),
        refresh_token: required_session_string(payload.fetch('refresh_token')),
        user_id: required_session_string(user.fetch('id')),
        user: user
      )
    end

    def parse_refresh_session(payload)
      owned_complete_session(build_session(payload))
    rescue KeyError, TypeError, NoMethodError, ArgumentError => e
      raise Error::TransportError, INCOMPLETE_SESSION, cause: e
    end

    def complete_session?(session)
      values = [session.access_token, session.refresh_token, session.user_id]
      values.all? { |value| value.is_a?(String) && !value.strip.empty? } &&
        matching_session_user?(session)
    end

    def matching_session_user?(session)
      session.user.nil? || (session.user.is_a?(Hash) && session.user['id'] == session.user_id)
    end

    def owned_complete_session(session)
      raise ArgumentError, INCOMPLETE_SESSION unless session.is_a?(Session) && complete_session?(session)

      owned_session(
        access_token: required_session_string(session.access_token),
        refresh_token: required_session_string(session.refresh_token),
        user_id: required_session_string(session.user_id),
        user: session.user
      )
    end

    def required_session_string(value)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, INCOMPLETE_SESSION
    end

    def owned_session(access_token:, refresh_token:, user_id:, user: nil)
      Session.new(
        access_token: access_token.dup.freeze,
        refresh_token: refresh_token.dup.freeze,
        user_id: user_id.dup.freeze,
        user: user
      )
    end
  end
end
