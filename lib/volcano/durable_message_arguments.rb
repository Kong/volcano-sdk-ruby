# frozen_string_literal: true

module Volcano
  # Checks durable message arguments before the generated client does, for the
  # reason DurableArguments gives.
  module DurableMessageArguments
    MESSAGE_NAME = /\A[ -~]{1,237}\z/
    HEADER_VALUE = /\A[ -~]+\z/
    MAX_IDEMPOTENCY_KEY_LENGTH = 255
    MAX_CLIENT_TOKEN_LENGTH = 128
    MAX_LIST_LIMIT = 500

    private

    def known_options(options, known)
      unknown = options.keys - known
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      options
    end

    def message_name(value)
      return value.dup.freeze if value.is_a?(String) && MESSAGE_NAME.match?(value)

      raise ArgumentError, 'name must be 1 to 237 printable ASCII characters'
    end

    # Sent as a header, which carries printable ASCII only.
    def bounded_text(value, field, limit)
      return if value.nil?
      return value.dup.freeze if value.is_a?(String) && HEADER_VALUE.match?(value) && value.length <= limit

      raise ArgumentError, "#{field} must be 1 to #{limit} printable ASCII characters"
    end

    def after_argument(value)
      return value if value.nil? || (value.is_a?(Integer) && !value.negative?)

      raise ArgumentError, 'after must be a non-negative Integer'
    end

    def limit_argument(value)
      return value if value.nil? || (value.is_a?(Integer) && value.between?(1, MAX_LIST_LIMIT))

      raise ArgumentError, "limit must be an Integer between 1 and #{MAX_LIST_LIMIT}"
    end
  end
  private_constant :DurableMessageArguments
end
