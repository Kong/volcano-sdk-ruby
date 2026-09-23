# frozen_string_literal: true

module Volcano
  # Authenticates users and updates the client session.
  class Auth
    include AuthRefresh
    include AuthSignOut
    include AuthProfile
    include AuthUpdateUser
    include AuthEmailChange
    include AuthSessions

    INCOMPLETE_SESSION = 'Expected a complete Volcano::Session'
    private_constant :INCOMPLETE_SESSION

    def initialize(client, transport, api_url:)
      @client = client
      @transport = transport
      @api_url = api_url
    end

    def current_session
      @client.current_session
    end

    def current_session=(session)
      @client.store_session(owned_complete_session(session), event: nil)
    end

    def on_auth_state_change(&callback)
      raise ArgumentError, 'callback block required' unless callback

      @client.subscribe_auth_state_change(&callback)
    end

    def sign_in(email:, password:)
      generation, = @client.capture_session
      sign_in_for_generation(email:, password:, generation:)
    end

    private

    def session_payload(status, decode: nil)
      binding = @client.capture_session_binding
      request = yield
      payload = Transport.body(session_request(binding: binding, &request), status)
      result = decode ? send(decode, payload) : payload
      owned_session_binding(binding)
      result
    end

    def sign_in_for_generation(email:, password:, generation:)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      payload = Transport.body(sign_in_response(email:, password:), 200)
      session = build_session(payload)
      raise Error::SessionChangedError unless @client.store_session_if_current?(session, generation)

      session
    end

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

    def build_session(payload)
      owned_session(
        access_token: payload.fetch('access_token'),
        refresh_token: payload.fetch('refresh_token'),
        user_id: payload.fetch('user').fetch('id'),
        user: payload.fetch('user')
      )
    end

    def parse_refresh_session(payload)
      owned_complete_session(build_session(payload))
    rescue KeyError, TypeError, NoMethodError, ArgumentError => e
      raise Error::TransportError, INCOMPLETE_SESSION, cause: e
    end

    def complete_session?(session)
      return false unless session.is_a?(Session)

      values = [session.access_token, session.refresh_token, session.user_id]
      values.all? { |value| value.is_a?(String) && !value.strip.empty? } &&
        matching_session_user?(session)
    end

    def matching_session_user?(session)
      session.user.nil? || (session.user.is_a?(Hash) && session.user['id'] == session.user_id)
    end

    def owned_complete_session(session)
      raise ArgumentError, INCOMPLETE_SESSION unless complete_session?(session)

      owned_session(**session.to_h)
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
