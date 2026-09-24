# frozen_string_literal: true

# Ruby SDK runtime and immutable caller-owned request values.
module Volcano
  # Copies JSON-like request values before storing them in builders or sending them.
  module ImmutableRequestValue
    def self.capture(value)
      # @type var active: Hash[Integer, bool]
      active = {}
      capture_value(value, active)
    rescue SystemStackError
      raise TypeError, 'Request value nesting is too deep'
    end

    def self.capture_value(value, active)
      case value
      when String, Time then value.dup.freeze
      when Array, Hash then capture_container(value, active)
      else value
      end
    end

    def self.capture_container(value, active)
      id = value.object_id
      raise TypeError, 'Request value contains a cycle' if active.key?(id)

      active[id] = true
      copy = value.is_a?(Array) ? value.map { |item| capture_value(item, active) } : capture_hash(value, active)
      active.delete(id)
      copy.freeze
    end

    def self.capture_hash(value, active)
      value.to_h { |key, item| [capture_value(key, active), capture_value(item, active)] }
    end
  end
  private_constant :ImmutableRequestValue
end
