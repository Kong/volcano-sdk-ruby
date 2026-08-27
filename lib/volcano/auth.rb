# frozen_string_literal: true

module Volcano
  class Auth
    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def sign_in(email:, password:)
      response = Transport.invoke do
        @transport.auth_signin(
          authorization: @client.anon_token,
          email: email,
          password: password
        )
      end
      payload = Transport.body(response, 200)
      session = Session.new(
        access_token: payload.fetch('access_token'),
        refresh_token: payload.fetch('refresh_token'),
        user_id: payload.fetch('user').fetch('id')
      )
      @client.store_session(session)
      session
    end
  end
end
