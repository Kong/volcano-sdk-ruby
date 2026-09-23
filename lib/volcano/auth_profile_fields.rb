# frozen_string_literal: true

require 'time'

module Volcano
  # Validates and maps the current-user JSON response.
  module AuthProfileFields
    INVALID_USER = 'Expected a complete user profile'
    RFC3339_OFFSET = /(?:[Zz]|[+-]\d{2}:\d{2})\z/
    USER_STATUSES = %w[active banned deleted].freeze
    private_constant :INVALID_USER, :RFC3339_OFFSET, :USER_STATUSES

    private

    def profile_user_payload(payload)
      raise Error::AuthenticationError, INVALID_USER unless payload.is_a?(Hash)

      profile_json_object(payload['user'])
    end

    def profile_json_object(payload)
      raise Error::AuthenticationError, INVALID_USER unless payload.is_a?(Hash)

      payload.to_h do |key, value|
        raise Error::AuthenticationError, INVALID_USER unless key.is_a?(String)

        [key, profile_json_value(value)]
      end
    end

    def profile_json_value(value)
      case value
      when Array then value.map { |item| profile_json_value(item) }
      when Hash then profile_json_object(value)
      else profile_json_scalar(value)
      end
    end

    def profile_json_scalar(value)
      case value
      when nil, true, false, Integer, String then value
      when Float then profile_finite_float(value)
      else raise Error::AuthenticationError, INVALID_USER
      end
    end

    def profile_finite_float(value)
      raise Error::AuthenticationError, INVALID_USER unless value.finite?

      value
    end

    def profile_required_string(value)
      raise Error::AuthenticationError, INVALID_USER unless value.is_a?(String)

      value
    end

    def profile_required_id(value)
      raise Error::AuthenticationError, INVALID_USER unless value.is_a?(String) && !value.strip.empty?

      value
    end

    def profile_status(value)
      raise Error::AuthenticationError, INVALID_USER unless value.is_a?(String) && USER_STATUSES.include?(value)

      value
    end

    def profile_optional_string(value)
      return if value.nil?

      profile_required_string(value)
    end

    def profile_optional_object(value)
      profile_json_object(value) unless value.nil?
    end

    def profile_optional_boolean(value)
      return if value.nil?
      return true if value == true
      return false if value == false

      raise Error::AuthenticationError, INVALID_USER
    end

    def profile_parse_time(value)
      return if value.nil?
      raise Error::AuthenticationError, INVALID_USER unless value.is_a?(String) && RFC3339_OFFSET.match?(value)

      Time.iso8601(value).freeze
    rescue ArgumentError
      raise Error::AuthenticationError, INVALID_USER
    end
  end
end
