# frozen_string_literal: true

module Volcano
  # Implements current-user identity and sign-in method operations.
  module AuthMethods
    METHOD_TYPES = %w[password oauth anonymous].freeze

    def list_identities
      payload = mapping(authenticated_body(:auth_list_identities, 200))
      array(payload['identities']).map { |item| build_auth_identity(mapping(item)) }.freeze
    end

    def unlink_identity(identity_id:)
      authenticated_body(:auth_unlink_identity, 204, identity_id:)
      nil
    end

    def list_methods
      payload = mapping(authenticated_body(:auth_list_methods, 200))
      array(payload['methods']).map { |item| build_auth_method(mapping(item)) }.freeze
    end

    def promote_method(method_id:)
      method = build_auth_method(mapping(authenticated_body(:auth_promote_method, 200, method_id:)))
      refresh_user_best_effort
      method
    end

    private

    def build_auth_identity(payload)
      AuthIdentity.new(
        id: payload.fetch('id'), email: payload.fetch('email'),
        email_verified: required_boolean(payload, 'email_verified'),
        is_primary: required_boolean(payload, 'is_primary'),
        created_at: required_time(payload, 'created_at')
      )
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def build_auth_method(payload)
      AuthMethod.new(**auth_method_attributes(payload))
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def auth_method_attributes(payload)
      {
        id: payload.fetch('id'), type: required_method_type(payload),
        provider: payload['provider'], identity_id: payload.fetch('identity_id'),
        email: payload.fetch('email'), is_primary: required_boolean(payload, 'is_primary'),
        last_used_at: optional_time(payload['last_used_at']),
        created_at: required_time(payload, 'created_at'),
        updated_at: required_time(payload, 'updated_at')
      }
    end

    def required_method_type(payload)
      value = payload.fetch('type')
      return value if METHOD_TYPES.include?(value)

      raise auth_response_error
    end

    def required_boolean(payload, key)
      value = payload.fetch(key)
      return value if [true, false].include?(value)

      raise auth_response_error
    end

    def required_time(payload, key)
      optional_time(payload.fetch(key)) || raise(auth_response_error)
    end
  end
  private_constant :AuthMethods
end
