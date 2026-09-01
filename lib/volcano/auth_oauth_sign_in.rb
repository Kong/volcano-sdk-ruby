# frozen_string_literal: true

require 'openssl'

module Volcano
  # OAuth sign-in initiation and callback exchange behavior.
  class Auth
    MAX_OAUTH_STATE_LENGTH = 255
    private_constant :MAX_OAUTH_STATE_LENGTH

    def sign_in_with_oauth(provider, redirect_to:, state:)
      @transport.auth_oauth_authorization_url(
        anon_key: @client.anon_token,
        provider: oauth_provider_name(provider),
        redirect_url: oauth_parameter(redirect_to),
        client_state: oauth_state(state)
      )
    end

    def exchange_oauth_code(code:, redirect_to:, state:, expected_state:)
      validate_oauth_callback_state(state, expected_state)
      generation, = @client.capture_session
      session = build_session(Transport.body(oauth_exchange_response(code, redirect_to), 200))
      raise Error::SessionChangedError unless @client.store_session_if_current(session, generation)

      session
    end

    private

    def oauth_exchange_response(code, redirect_to)
      Transport.invoke do
        @transport.auth_oauth_exchange(
          authorization: @client.anon_token,
          code: oauth_parameter(code),
          redirect_url: oauth_parameter(redirect_to)
        )
      end
    end

    def oauth_parameter(value)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, 'OAuth parameters must be non-empty strings'
    end

    def oauth_state(value)
      state = oauth_parameter(value)
      raise ArgumentError, 'OAuth state must not exceed 255 characters' if state.length > MAX_OAUTH_STATE_LENGTH

      state
    end

    def validate_oauth_callback_state(state, expected_state)
      actual = oauth_state(state)
      expected = oauth_state(expected_state)
      valid = actual.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(actual, expected)
      raise ArgumentError, 'OAuth state mismatch' unless valid
    end
  end
end
