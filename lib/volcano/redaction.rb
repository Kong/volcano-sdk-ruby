# frozen_string_literal: true

require 'uri'

module Volcano
  # Removes credentials from exception messages before they cross the SDK boundary.
  module Redaction
    MARKER = '[REDACTED]'

    module_function

    def message(value, secrets:)
      variants(secrets).reduce(value.to_s.dup) do |redacted, secret|
        redacted.gsub(secret, MARKER)
      end
    end

    def exception(error, secrets:)
      redacted = copy_exception(error, message(error.message, secrets: secrets))
      redacted.set_backtrace(error.backtrace)
      redacted
    end

    def copy_exception(error, redacted_message)
      return copy_volcano_error(error, redacted_message) if volcano_error?(error)
      return error.class.new(redacted_message, code: error.code) if realtime_server_error?(error)

      error.exception(redacted_message)
    end

    def copy_volcano_error(error, redacted_message)
      error.class.new(
        redacted_message,
        status: error.status,
        code: error.code,
        retry_after: error.retry_after
      )
    end

    def volcano_error?(error)
      defined?(Error::VolcanoError) && error.is_a?(Error::VolcanoError)
    end

    def realtime_server_error?(error)
      defined?(Realtime::ServerError) && error.is_a?(Realtime::ServerError)
    end

    def variants(secrets)
      values = Array(secrets).compact.flat_map { |value| secret_variants(value) }
      values.uniq.sort_by { |value| -value.length }
    end

    def secret_variants(value)
      secret = value.to_s
      return [] if secret.empty?

      encoded = URI.encode_www_form_component(secret)
      [secret, encoded, encoded.gsub('+', '%20')]
    end
    private_class_method :copy_exception, :copy_volcano_error, :realtime_server_error?, :secret_variants, :variants,
                         :volcano_error?
  end
end
