# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Converts normalized response hashes into public immutable values.
  module AuthMapping
    OPTIONAL_SESSION_TIME_FIELDS = %i[
      last_activity_at session_started_at created_at updated_at
    ].freeze

    private

    def build_message(payload)
      message = payload['message']
      raise auth_response_error unless message.nil? || message.is_a?(String)

      MessageResult.new(message:)
    end

    def build_oauth_token(payload, provider)
      OAuthTokenResult.new(
        provider:,
        expires_in: payload['expires_in'],
        message: payload['message']
      )
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def build_auth_session(payload)
      AuthSession.new(**auth_session_attributes(payload))
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def auth_session_attributes(payload)
      {
        id: payload.fetch('id'), user_id: payload.fetch('user_id'),
        provider: payload.fetch('provider'), is_active: payload.fetch('is_active'),
        is_current: payload.fetch('is_current'), user_agent: payload['user_agent'],
        ip_address: payload['ip_address'], last_ip_address: payload['last_ip_address'],
        expires_at: required_time(payload, 'expires_at'),
        **session_time_attributes(payload)
      }
    end

    def session_time_attributes(payload)
      OPTIONAL_SESSION_TIME_FIELDS.to_h do |field|
        [field, optional_time(payload[field.to_s])]
      end
    end

    def required_time(payload, field)
      value = optional_time(payload.fetch(field))
      return value if value

      raise auth_response_error
    end

    def mapping(value)
      return value if value.is_a?(Hash)

      raise auth_response_error
    end

    def array(value)
      return value if value.is_a?(Array)

      raise auth_response_error
    end

    def optional_time(value)
      return value if value.is_a?(Time)

      value && Time.iso8601(value.to_s)
    rescue ArgumentError
      raise auth_response_error
    end

    def validate_provider(provider)
      value = provider.to_s
      return value if %w[google github microsoft apple].include?(value)

      raise Error::ValidationError, 'Unsupported OAuth provider'
    end

    def response_header(response, name)
      value = response.headers&.find { |key, _| key.casecmp?(name) }&.last
      raise auth_response_error('Missing authorization URL') unless value

      value
    end

    def secure_state?(state, expected_state)
      return false unless state.is_a?(String) && expected_state.is_a?(String)

      state.bytesize == expected_state.bytesize && OpenSSL.secure_compare(state, expected_state)
    end
  end
  private_constant :AuthMapping
end
