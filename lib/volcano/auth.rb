# frozen_string_literal: true

module Volcano
  # Authenticates users and updates the client session.
  class Auth
    INCOMPLETE_SESSION = 'Expected a complete Volcano::Session'
    private_constant :INCOMPLETE_SESSION

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def current_session
      @client.current_session
    end

    def current_session=(session)
      raise ArgumentError, INCOMPLETE_SESSION unless complete_session?(session)

      @client.store_session(owned_session(**session.to_h))
    end

    def on_auth_state_change(&callback)
      raise ArgumentError, 'callback block required' unless callback

      @client.subscribe_auth_state_change(&callback)
    end

    def sign_in(email:, password:)
      payload = Transport.body(sign_in_response(email:, password:), 200)
      session = build_session(payload)
      @client.store_session(session)
      session
    end

    def refresh_session
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      session = build_session(refresh_payload(current.refresh_token, generation))
      stored = @client.store_session_if_current?(session, generation, event: :token_refreshed)
      raise Error::SessionChangedError unless stored

      session
    end

    def sign_out
      generation, current = @client.capture_session
      return unless current

      error = revocation_error(current.refresh_token)
      raise Error::SessionChangedError, cause: error unless @client.clear_session_if_current?(generation)

      raise error if error
    end

    private

    def sign_in_response(email:, password:)
      Transport.invoke do
        @transport.auth_signin(
          authorization: @client.anon_token,
          email: email,
          password: password
        )
      end
    end

    def refresh_response(refresh_token)
      Transport.invoke do
        @transport.auth_refresh(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def logout_response(refresh_token)
      Transport.invoke do
        @transport.auth_logout(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def revocation_error(refresh_token)
      Transport.body(logout_response(refresh_token), 204)
      nil
    rescue Error::VolcanoError => e
      e
    end

    def refresh_payload(refresh_token, generation)
      Transport.body(refresh_response(refresh_token), 200)
    rescue Error::AuthenticationError
      @client.clear_session_if_current?(generation)
      raise
    end

    def build_session(payload)
      owned_session(
        access_token: payload.fetch('access_token'),
        refresh_token: payload.fetch('refresh_token'),
        user_id: payload.fetch('user').fetch('id')
      )
    end

    def complete_session?(session)
      return false unless session.is_a?(Session)

      session.to_h.values.all? { |value| value.is_a?(String) && !value.strip.empty? }
    end

    def owned_session(access_token:, refresh_token:, user_id:)
      Session.new(
        access_token: access_token.dup.freeze,
        refresh_token: refresh_token.dup.freeze,
        user_id: user_id.dup.freeze
      )
    end
  end
end
