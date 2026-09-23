# frozen_string_literal: true

require 'timeout'
require 'socket'

module Volcano
  # Normalizes transport responses and maps failures to public SDK errors.
  module Transport
    Response = Data.define(:status, :body, :headers, :data)

    ERROR_TYPES = {
      400 => Error::ValidationError,
      401 => Error::AuthenticationError,
      403 => Error::AuthenticationError,
      404 => Error::NotFoundError,
      409 => Error::ConflictError,
      422 => Error::ValidationError,
      429 => Error::RateLimitedError
    }.freeze

    NETWORK_ERRORS = [IOError, SystemCallError, SocketError, Timeout::Error].freeze

    def self.invoke
      yield
    rescue IOError, SystemCallError, SocketError, Timeout::Error => e
      raise Error::TransportError, e.message, cause: e
    end

    def self.body(response, expected_status)
      return response.body if response.status == expected_status

      raise response_error(response)
    end

    def self.response_error(response)
      # @type var payload: Hash[String, Object?]
      payload = response.body.is_a?(Hash) ? response.body : {}
      retry_after = integer_header(response.headers, 'Retry-After') if response.status == 429
      error_type(response.status).new(
        error_message(payload),
        status: response.status,
        code: payload['code']&.to_s,
        retry_after: retry_after
      )
    end

    def self.error_message(payload)
      error = payload['error']
      return error if error.is_a?(String)

      message = payload['message']
      message.is_a?(String) ? message : 'Volcano request failed'
    end

    def self.json_value(value)
      case value
      when Array then value.map { |entry| json_value(entry) }
      when Hash then json_object(value)
      else json_scalar(value)
      end
    end

    def self.json_object(value, message: 'Expected a JSON object')
      raise TypeError, message unless value.is_a?(Hash)

      value.to_h do |key, item|
        raise TypeError, message unless key.is_a?(String)

        [key, json_value(item)]
      end
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

    def self.error_type(status)
      ERROR_TYPES.fetch(status) do
        status.between?(500, 599) ? Error::ServerError : Error::VolcanoError
      end
    end

    def self.integer_header(headers, name)
      value = headers&.find { |key, _| key.casecmp?(name) }&.last
      Integer(value, exception: false)
    end
    private_class_method :error_type, :integer_header, :response_error, :finite_float, :json_scalar
  end
end
