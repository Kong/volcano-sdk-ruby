# frozen_string_literal: true

require 'time'

module Volcano
  # Validates lock response fields before creating public records.
  module LockResponse
    private

    def parse_time(value)
      return Time.iso8601(value) if value.is_a?(String)
      return value if value.nil? || value.is_a?(Time)

      raise Error::TransportError, 'invalid lock expiry'
    rescue ArgumentError => e
      raise Error::TransportError, 'invalid lock expiry', cause: e
    end

    def lock_payload(body)
      raise Error::TransportError, 'invalid lock response' unless body.is_a?(Hash)

      body
    end

    def lock_held(value)
      return true if value == true
      return false if value == false

      raise Error::TransportError, 'invalid lock held flag'
    end

    def required_fencing_token(value)
      raise Error::TransportError, 'invalid lock fencing token' unless value.is_a?(Integer)

      value
    end

    def optional_fencing_token(value)
      return if value.nil?

      required_fencing_token(value)
    end
  end
end
