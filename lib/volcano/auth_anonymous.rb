# frozen_string_literal: true

module Volcano
  # Anonymous sign-in behavior for the authentication facade.
  class Auth
    def sign_in_anonymously(metadata: {})
      generation, = @client.capture_session
      payload = Transport.body(anonymous_signin_response(metadata), 201)
      session = build_session(payload)
      raise Error::SessionChangedError unless @client.store_session_if_current?(session, generation)

      session
    end

    def convert_anonymous(email:, password:, metadata: {})
      profile_request do
        request_email = email.dup.freeze
        request_password = password.dup.freeze
        request_metadata = JSON.parse(JSON.generate(Hash(metadata)), freeze: true)
        ->(token) { anonymous_conversion_response(token, request_email, request_password, request_metadata) }
      end
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
