# frozen_string_literal: true

module Volcano
  # Implements password-policy, device authorization, and platform exchange.
  module AuthDevice
    DEVICE_ACTIONS = %w[approve deny].freeze

    def password_policy
      build_password_policy(mapping(anonymous_body(:auth_get_password_policy, 200)))
    end

    def start_device_authorization(client_id:)
      payload = anonymous_body(:auth_device_authorize, 200, client_id:)
      build_device_authorization(mapping(payload))
    end

    def poll_device_token(client_id:, device_code:)
      payload = anonymous_body(
        :auth_device_token, 200, secrets: [device_code], client_id:, device_code:
      )
      commit_session(mapping(payload))
    end

    def verify_device(user_code:, action: 'approve')
      validate_device_action(action)
      payload = mapping(authenticated_body(:auth_device_verify, 200, user_code:, action:))
      build_device_verification(payload)
    end

    def exchange_platform_token(client_id:)
      payload = mapping(authenticated_body(:auth_platform_exchange, 200, client_id:))
      PlatformToken.new(
        token: payload.fetch('token'), user_id: payload.fetch('user_id'),
        token_id: payload.fetch('token_id'), expires_at: required_time(payload, 'expires_at')
      )
    rescue KeyError, TypeError
      raise auth_response_error
    end

    private

    def build_password_policy(payload)
      fields = PasswordPolicy.members.to_h do |field|
        value = payload.fetch(field.to_s)
        [field, password_policy_value(field, value)]
      end
      PasswordPolicy.new(**fields)
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def password_policy_value(field, value)
      integer_fields = %i[effective_min_length min_configurable_length max_length]
      return value if integer_fields.include?(field) && value.is_a?(Integer)
      return value if !integer_fields.include?(field) && [true, false].include?(value)

      raise auth_response_error
    end

    def build_device_authorization(payload)
      DeviceAuthorization.new(**DeviceAuthorization.members.to_h { |field| [field, payload.fetch(field.to_s)] })
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def build_device_verification(payload)
      success = payload['success']
      status = payload['status']
      raise auth_response_error unless success.nil? || [true, false].include?(success)
      raise auth_response_error unless status.nil? || status.is_a?(String)

      DeviceVerification.new(success:, status:)
    end

    def validate_device_action(action)
      return if DEVICE_ACTIONS.include?(action)

      raise Error::ValidationError, 'Device action must be approve or deny'
    end
  end
  private_constant :AuthDevice
end
