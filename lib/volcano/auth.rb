# frozen_string_literal: true

module Volcano
  # Authenticates users and updates the client session.
  class Auth
    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def sign_in(email:, password:)
      payload = Transport.body(sign_in_response(email:, password:), 200)
      session = build_session(payload)
      @client.store_session(session)
      session
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

    def build_session(payload)
      Session.new(
        access_token: payload.fetch('access_token'),
        refresh_token: payload.fetch('refresh_token'),
        user_id: payload.fetch('user').fetch('id')
      )
    end
  end
end
