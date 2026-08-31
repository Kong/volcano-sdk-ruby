# frozen_string_literal: true

module Volcano
  # Server-validated current-user behavior for the authentication facade.
  class Auth
    INVALID_USER = 'Expected a complete user profile'
    private_constant :INVALID_USER

    def user
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      payload = Transport.body(get_user_response(current.access_token), 200)
      user = build_user(user_payload(payload))
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      user
    end

    alias get_user user

    private

    def get_user_response(access_token)
      Transport.invoke do
        @transport.auth_get_user(authorization: access_token)
      end
    end

    def build_user(payload)
      raise Error::AuthenticationError, INVALID_USER unless valid_user?(payload)

      User.new(
        id: payload.fetch('id'),
        project_id: payload['project_id'],
        email: payload.fetch('email'),
        email_confirmed: payload['email_confirmed'],
        user_metadata: payload['user_metadata'],
        app_metadata: payload['app_metadata'],
        avatar_url: payload['avatar_url'],
        status: payload.fetch('status'),
        banned_until: payload['banned_until'],
        last_sign_in_at: payload['last_sign_in_at'],
        created_at: payload['created_at'],
        updated_at: payload['updated_at']
      )
    end

    def user_payload(payload)
      raise Error::AuthenticationError, INVALID_USER unless payload.is_a?(Hash)

      payload['user']
    end

    def valid_user?(payload)
      return false unless payload.is_a?(Hash)

      required_user_fields?(payload) && valid_email_confirmation?(payload) && valid_metadata?(payload)
    end

    def required_user_fields?(payload)
      %w[id status].all? { |name| complete_string?(payload[name]) } && payload['email'].is_a?(String)
    end

    def valid_email_confirmation?(payload)
      [true, false, nil].include?(payload['email_confirmed'])
    end

    def valid_metadata?(payload)
      %w[user_metadata app_metadata].all? do |name|
        payload[name].nil? || payload[name].is_a?(Hash)
      end
    end

    def complete_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
