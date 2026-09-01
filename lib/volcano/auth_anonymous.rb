# frozen_string_literal: true

module Volcano
  # Anonymous sign-in behavior for the authentication facade.
  class Auth
    def sign_in_anonymously(metadata: {})
      generation, = @client.capture_session
      payload = Transport.body(anonymous_signin_response(metadata), 201)
      session = build_session(payload)
      raise Error::SessionChangedError unless @client.store_session_if_current(session, generation)

      session
    end

    def convert_anonymous(email:, password:, metadata: {})
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      payload = Transport.body(
        anonymous_conversion_response(current.access_token, email, password, metadata),
        200
      )
      user = build_user(user_payload(payload))
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      user
    end

    private

    def anonymous_signin_response(metadata)
      Transport.invoke do
        @transport.auth_signup_anonymous(
          authorization: @client.anon_token,
          metadata: Hash(metadata)
        )
      end
    end

    def anonymous_conversion_response(access_token, email, password, metadata)
      Transport.invoke do
        @transport.auth_convert_anonymous(
          authorization: access_token,
          email: email,
          password: password,
          metadata: Hash(metadata)
        )
      end
    end
  end
end
