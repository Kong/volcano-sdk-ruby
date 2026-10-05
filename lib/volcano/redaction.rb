# frozen_string_literal: true

require 'uri'

module Volcano
  # Removes credentials from exception messages before they cross the SDK boundary.
  module Redaction
    MARKER = '[REDACTED]'

    def self.message(value, secrets:)
      variants(secrets).reduce(value.to_s.dup) do |redacted, secret|
        redacted.gsub(secret, MARKER)
      end
    end

    def self.exception(error, secrets:)
      redacted = copy_exception(error, message(error.message, secrets: secrets))
      trace = error.backtrace
      redacted.set_backtrace(trace.map(&:to_s)) if trace
      redacted
    end

    def self.copy_exception(error, redacted_message)
      if defined?(Error::VolcanoError) && error.is_a?(Error::VolcanoError)
        return copy_volcano_error(error, redacted_message)
      end
      if defined?(Realtime::ServerError) && error.is_a?(Realtime::ServerError)
        return error.class.new(redacted_message, code: error.code)
      end

      error.exception(redacted_message)
    end

    def self.copy_volcano_error(error, redacted_message)
      error.class.new(
        redacted_message,
        status: error.status,
        code: error.code,
        retry_after: error.retry_after
      )
    end

    def self.variants(secrets)
      values = Array(secrets).compact.flat_map do |value|
        secret = value.to_s
        next [] if secret.empty?

        encoded = URI.encode_www_form_component(secret)
        [secret, encoded, encoded.gsub('+', '%20')]
      end
      values.uniq.sort_by { |value| -value.length }
    end
    private_class_method :copy_exception, :copy_volcano_error, :variants
  end
end
