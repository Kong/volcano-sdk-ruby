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
    include AuthSessionConstruction

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
  end
end
