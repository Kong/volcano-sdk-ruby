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

    private

    def anonymous_signin_response(metadata)
      Transport.invoke do
        @transport.auth_signup_anonymous(
          authorization: @client.anon_token,
          metadata: Hash(metadata)
        )
      end
    end
  end
end
