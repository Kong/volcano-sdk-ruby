# frozen_string_literal: true

require 'time'

module Volcano
  # Server-validated current-user behavior for the authentication facade.
  class Auth
    INVALID_USER = 'Expected a complete user profile'
    RFC3339_OFFSET = /(?:[Zz]|[+-]\d{2}:\d{2})\z/
    USER_OPTIONAL_VALUES = %w[project_id email_confirmed user_metadata app_metadata avatar_url].freeze
    USER_OPTIONAL_STRINGS = %w[project_id avatar_url].freeze
    USER_STATUSES = %w[active banned deleted].freeze
    USER_TIMESTAMPS = %w[banned_until last_sign_in_at created_at updated_at].freeze
    private_constant :INVALID_USER, :RFC3339_OFFSET, :USER_OPTIONAL_STRINGS,
                     :USER_OPTIONAL_VALUES, :USER_STATUSES, :USER_TIMESTAMPS

    def user
      profile_request { method(:get_user_response) }
    end

    alias get_user user

    private

    def profile_request
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      request = yield
      payload = Transport.body(session_request(binding: binding, &request), 200)
      cache_current_user(payload, owned_session_binding(binding).first)
    end

    def cache_current_user(payload, generation)
      profile = user_payload(payload)
      user = build_user(profile)
      raise Error::SessionChangedError unless @client.update_session_user_if_current?(profile, generation)

      user
    end

    def get_user_response(access_token)
      Transport.invoke do
        @transport.auth_get_user(authorization: access_token)
      end
    end

    def build_user(payload)
      raise Error::AuthenticationError, INVALID_USER unless valid_user?(payload)

      User.new(**user_attributes(payload))
    rescue ArgumentError => e
      raise Error::AuthenticationError, INVALID_USER, cause: e
    end

    def user_attributes(payload)
      {
        id: payload.fetch('id'),
        email: payload.fetch('email'),
        status: payload.fetch('status'),
        **USER_OPTIONAL_VALUES.to_h { |name| [name.to_sym, payload[name]] },
        **USER_TIMESTAMPS.to_h { |name| [name.to_sym, parse_time(payload[name])] }
      }
    end

    def user_payload(payload)
      raise Error::AuthenticationError, INVALID_USER unless payload.is_a?(Hash)

      payload['user']
    end

    def valid_user?(payload)
      return false unless payload.is_a?(Hash)

      required_user_fields?(payload) && valid_email_confirmation?(payload) &&
        valid_metadata?(payload) && valid_optional_strings?(payload) && valid_timestamps?(payload)
    end

    def required_user_fields?(payload)
      complete_string?(payload['id']) && payload['email'].is_a?(String) &&
        USER_STATUSES.include?(payload['status'])
    end

    def valid_email_confirmation?(payload)
      [true, false, nil].include?(payload['email_confirmed'])
    end

    def valid_metadata?(payload)
      %w[user_metadata app_metadata].all? do |name|
        payload[name].nil? || payload[name].is_a?(Hash)
      end
    end

    def valid_optional_strings?(payload)
      USER_OPTIONAL_STRINGS.all? do |name|
        payload[name].nil? || payload[name].is_a?(String)
      end
    end

    def valid_timestamps?(payload)
      USER_TIMESTAMPS.all? { |name| valid_timestamp?(payload[name]) }
    end

    def valid_timestamp?(value)
      return true if value.nil?

      value.is_a?(String) && RFC3339_OFFSET.match?(value) && Time.iso8601(value)
    rescue ArgumentError
      false
    end

    def parse_time(value)
      Time.iso8601(value).freeze unless value.nil?
    end

    def complete_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
