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
      user = build_user(payload['user'])
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
        email: payload.fetch('email'),
        status: payload.fetch('status'),
        email_confirmed: payload['email_confirmed'],
        user_metadata: payload['user_metadata']
      )
    end

    def valid_user?(payload)
      return false unless payload.is_a?(Hash)

      nonempty = %w[id status].all? { |name| complete_string?(payload[name]) }
      email = payload['email'].is_a?(String)
      confirmed = [true, false, nil].include?(payload['email_confirmed'])
      metadata = payload['user_metadata'].nil? || payload['user_metadata'].is_a?(Hash)
      nonempty && email && confirmed && metadata
    end

    def complete_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
