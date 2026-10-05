# frozen_string_literal: true

require 'json'

module Volcano
  # Validates and copies JSON response values from function and database transports.
  module Transport
    def self.json_value(value)
      # @type var active: Hash[Integer, bool]
      active = {}
      copy = json_copy(value, active)
      validate_json_encoding(copy)
      copy
    end

    def self.json_copy(value, active)
      case value
      when Array then json_container(value, active) { value.map { |entry| json_copy(entry, active) } }
      when Hash then json_hash(value, active, message: 'Expected a JSON object')
      else json_scalar(value)
      end
    end

    def self.json_object(value, message: 'Expected a JSON object')
      # @type var active: Hash[Integer, bool]
      active = {}
      copy = json_hash(value, active, message:)
      validate_json_encoding(copy)
      copy
    end

    def self.json_hash(value, active, message:)
      raise TypeError, message unless value.is_a?(Hash)

      json_container(value, active) do
        value.to_h do |key, item|
          raise TypeError, message unless key.is_a?(String)

          [key, json_copy(item, active)]
        end
      end
    end

    def self.json_container(value, active)
      id = value.object_id
      raise TypeError, 'Expected a JSON response' if active.key?(id) || active.size >= 100

      active[id] = true
      copy = yield
      active.delete(id)
      copy
    end

    def self.validate_json_encoding(value)
      JSON.generate(value)
      nil
    rescue JSON::GeneratorError
      raise TypeError, 'Expected a JSON response', cause: nil
    end

    def self.json_rows(value)
      rows = json_object(value)['data']
      raise TypeError, 'Expected database rows' unless rows.is_a?(Array)

      rows.map { |row| json_object(row) }
    end

    def self.finite_float(value)
      raise TypeError, 'Expected a finite JSON number' unless value.finite?

      value
    end

    def self.json_scalar(value)
      case value
      when NilClass, TrueClass, FalseClass, Integer, String then value
      when Float then finite_float(value)
      else raise TypeError, 'Expected a JSON response'
      end
    end

    private_class_method :json_copy, :json_hash, :json_container, :validate_json_encoding, :finite_float, :json_scalar
  end
end
