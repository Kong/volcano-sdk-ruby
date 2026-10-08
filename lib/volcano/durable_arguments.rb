# frozen_string_literal: true

require 'time'

module Volcano
  # Checks durable arguments before the generated client does. It enforces the
  # same bounds but raises its own message, naming the operation and the option
  # key it knows the value by; checked here, the caller reads a message about
  # the argument they passed, the way Functions#invoke does for a function name.
  module DurableArguments
    # The page size the platform serves at most, mirrored from the wire contract.
    MAX_PAGE_SIZE = 100
    RFC3339_OFFSET = /(?:[Zz]|[+-]\d{2}:\d{2})\z/
    private_constant :RFC3339_OFFSET

    private

    # An empty path segment would address the collection instead of the
    # resource, which is a different request rather than a failed one.
    def identifier(value, field)
      raise ArgumentError, "#{field} must be a non-empty String" unless value.is_a?(String) && !value.strip.empty?

      value.strip.freeze
    end

    def validate_paging(page, limit)
      raise ArgumentError, 'page must be a positive Integer' unless page.nil? || positive_integer?(page)

      validate_page_limit(limit)
    end

    def validate_page_limit(limit)
      return if limit.nil? || (limit.is_a?(Integer) && positive_integer?(limit) && limit <= MAX_PAGE_SIZE)

      raise ArgumentError, "limit must be an Integer between 1 and #{MAX_PAGE_SIZE}"
    end

    def positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end

    # Sent in UTC with nanoseconds, so a bound keeps the caller's precision.
    def timestamp_argument(value, field)
      return if value.nil?

      (value.is_a?(Time) ? value : offset_time(value)).getutc.iso8601(9)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{field} must be a Time or an ISO 8601 timestamp with an offset", cause: nil
    end

    # Time.iso8601 reads a string without an offset in the host's time zone.
    def offset_time(value)
      raise TypeError unless value.is_a?(String) && RFC3339_OFFSET.match?(value)

      Time.iso8601(value)
    end
  end
  private_constant :DurableArguments
end
