# frozen_string_literal: true

module Volcano
  # Session-less sign-up behavior for the authentication facade.
  class Auth
    INVALID_SIGN_UP_RESULT = 'Expected a complete sign-up acknowledgement'
    private_constant :INVALID_SIGN_UP_RESULT

    def sign_up(email:, password:, metadata: {})
      payload = Transport.body(sign_up_response(email:, password:, metadata:), 201)
      build_sign_up_result(payload)
    end

    private

    def sign_up_response(email:, password:, metadata:)
      Transport.invoke do
        @transport.auth_signup(
          authorization: @client.anon_token,
          email: email,
          password: password,
          metadata: Hash(metadata)
        )
      end
    end

    def build_sign_up_result(payload)
      confirmation_required = payload.fetch('confirmation_required')
      message = payload.fetch('message')
      valid = [true, false].include?(confirmation_required) && message.is_a?(String)
      raise TypeError, INVALID_SIGN_UP_RESULT unless valid

      SignUpResult.new(confirmation_required: confirmation_required, message: message.dup.freeze)
    end
  end
end
