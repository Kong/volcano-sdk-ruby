# frozen_string_literal: true

require 'uri'

module Volcano
  module Redaction
    MARKER = '[REDACTED]'

    module_function

    def message(value, secrets:)
      variants(secrets).reduce(value.to_s.dup) do |redacted, secret|
        redacted.gsub(secret, MARKER)
      end
    end

    def exception(error, secrets:)
      redacted = if defined?(Error::VolcanoError) && error.is_a?(Error::VolcanoError)
                   error.class.new(
                     message(error.message, secrets: secrets),
                     status: error.status,
                     code: error.code,
                     retry_after: error.retry_after
                   )
                 elsif defined?(Realtime::ServerError) && error.is_a?(Realtime::ServerError)
                   error.class.new(message(error.message, secrets: secrets), code: error.code)
                 else
                   error.exception(message(error.message, secrets: secrets))
                 end
      redacted.set_backtrace(error.backtrace)
      redacted
    end

    def variants(secrets)
      values = Array(secrets).compact.flat_map do |value|
        secret = value.to_s
        next [] if secret.empty?

        encoded = URI.encode_www_form_component(secret)
        [secret, encoded, encoded.gsub('+', '%20')]
      end
      values.uniq.sort_by { |value| -value.length }
    end
    private_class_method :variants
  end
end
