# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Implements sign-up, sign-in, refresh, user, and listener lifecycle.
  module AuthLifecycle
    def sign_up(email:, password:, user_metadata: nil, sign_in: false)
      payload = anonymous_body(
        :auth_signup, 201, secrets: [password], email:, password:, user_metadata:
      )
      result = signup_result(mapping(payload))
      return result unless sign_in && !result.confirmation_required

      session = sign_in(email:, password:)
      SignUpResult.new(
        confirmation_required: result.confirmation_required, message: result.message,
        user: @client.current_user, session:
      )
    end

    def sign_in(email:, password:)
      payload = anonymous_body(:auth_signin, 200, secrets: [password], email:, password:)
      commit_session(mapping(payload))
    end

    def sign_out
      synchronize_auth_operation do
        session = @client.current_session
        begin
          revoke_session(session) if session&.refresh_token
        ensure
          @client.clear_auth
        end
      end
    end

    def fetch_user
      synchronize_auth_operation do
        payload = authenticated_body(:auth_get_user, 200)
        build_user(mapping(mapping(payload).fetch('user'))).tap { |user| @client.store_user(user) }
      end
    rescue KeyError
      raise auth_response_error
    end
    alias get_user fetch_user
    private :fetch_user

    def update_user(password: nil, user_metadata: nil)
      synchronize_auth_operation do
        payload = authenticated_body(
          :auth_update_user, 200, secrets: [password], password:, user_metadata:
        )
        build_user(mapping(mapping(payload).fetch('user'))).tap { |user| @client.store_user(user) }
      end
    rescue KeyError
      raise auth_response_error
    end

    def refresh_session
      synchronize_auth_operation { @refresh_mutex.synchronize { refresh_current_session } }
    end

    def on_auth_state_change(listener = nil, &block)
      callback = listener || block
      raise ArgumentError, 'listener or block is required' unless callback

      @client.subscribe_auth(callback)
    end

    private

    def refresh_session_for(rejected_session)
      @refresh_mutex.synchronize do
        refresh_current_session if @client.current_session.equal?(rejected_session)
      end
    end

    def refresh_current_session
      session = refreshable_session
      commit_session(mapping(refresh_payload(session)))
    rescue StandardError
      @client.clear_auth if @client.current_session.equal?(session)
      raise
    end

    def refreshable_session
      session = @client.current_session
      return session if session&.refresh_token

      missing_refresh
    end

    def refresh_payload(session)
      anonymous_body(
        :auth_refresh, 200, secrets: [session.refresh_token], refresh_token: session.refresh_token
      )
    end

    def signup_result(payload)
      SignUpResult.new(
        confirmation_required: payload['confirmation_required'] == true,
        message: payload['message'].to_s
      )
    end

    def commit_session(payload)
      synchronize_auth_operation do
        session, user = build_session(payload)
        @current_device_session_ids = [].freeze
        @client.commit_auth(session, user)
        session
      end
    end

    def revoke_session(session)
      anonymous_body(
        :auth_logout, 204, secrets: [session.refresh_token], refresh_token: session.refresh_token
      )
    end

    def missing_refresh
      @client.clear_auth
      raise Error::AuthenticationError, 'No refresh token available'
    end
  end
  private_constant :AuthLifecycle
end
