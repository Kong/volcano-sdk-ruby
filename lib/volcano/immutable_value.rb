# frozen_string_literal: true

module Volcano
  # Recursively copies JSON-like values into immutable public data.
  module ImmutableValue
    USER_DEFAULTS = {
      project_id: nil, email_confirmed: nil, user_metadata: nil,
      app_metadata: nil, avatar_url: nil, status: nil, banned_until: nil,
      last_sign_in_at: nil, created_at: nil, updated_at: nil
    }.freeze

    module_function

    def copy(value)
      case value
      when Hash then copy_hash(value)
      when Array then value.map { |item| copy(item) }.freeze
      else copy_scalar(value)
      end
    end

    def copy_hash(value)
      value.to_h { |key, item| [key.to_s.dup.freeze, copy(item)] }.freeze
    end

    def copy_scalar(value)
      return if value.nil?

      copied = value.is_a?(String) || value.is_a?(Time) ? value.dup : value
      copied.freeze
    end

    def user_attributes(attributes)
      validate_user_attributes(attributes)
      copy_attributes(**USER_DEFAULTS, **attributes)
    end

    def copy_attributes(**values)
      values.transform_values { |value| copy(value) }
    end

    def validate_user_attributes(attributes)
      unknown = attributes.keys - USER_DEFAULTS.keys
      raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?
    end
  end
  private_constant :ImmutableValue
end
