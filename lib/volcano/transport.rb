# frozen_string_literal: true

require 'timeout'
require 'socket'

module Volcano
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

    module_function

    def invoke
      yield
    rescue *NETWORK_ERRORS => e
      raise Error::TransportError, e.message, cause: e
    end

    def body(response, expected_status)
      return response.body if response.status == expected_status

      payload = response.body.is_a?(Hash) ? response.body : {}
      error_type = ERROR_TYPES.fetch(response.status) do
        response.status.between?(500, 599) ? Error::ServerError : Error::VolcanoError
      end
      retry_after = integer_header(response.headers, 'Retry-After') if response.status == 429
      raise error_type.new(
        payload['error'] || payload['message'] || 'Volcano request failed',
        status: response.status,
        code: payload['code']&.to_s,
        retry_after: retry_after
      )
    end

    def integer_header(headers, name)
      value = headers&.find { |key, _| key.casecmp?(name) }&.last
      Integer(value, exception: false)
    end
    private_class_method :integer_header
  end
end
