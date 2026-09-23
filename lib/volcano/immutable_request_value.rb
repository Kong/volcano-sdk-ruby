# frozen_string_literal: true

# Ruby SDK runtime and immutable caller-owned request values.
module Volcano
  # Copies JSON-like request values before storing them in builders or sending them.
  module ImmutableRequestValue
    def self.capture(value)
      case value
      when String, Time then value.dup.freeze
      when Array then value.map { |item| capture(item) }.freeze
      when Hash then capture_hash(value)
      else value
      end
    end

    def self.capture_hash(value)
      value.to_h { |key, item| [capture(key), capture(item)] }.freeze
    end
  end
  private_constant :ImmutableRequestValue
end
