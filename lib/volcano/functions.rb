# frozen_string_literal: true

module Volcano
  # Invokes deployed Volcano functions by name.
  class Functions
    FUNCTION_NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
    private_constant :FUNCTION_NAME

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def invoke(name, payload = {})
      validate_invocation(name, payload)
      authorization = @client.function_token
      resolved = Transport.invoke do
        @transport.resolve_function_for_invocation(authorization: authorization, name: name)
      end
      function_id = resolved_function_id(Transport.body(resolved, 200))
      response = Transport.invoke do
        @transport.invoke_function(
          authorization: authorization, function_id: function_id, payload: payload.dup
        )
      end
      function_response(response)
    end

    private

    def validate_invocation(name, payload)
      unless name.is_a?(String) && FUNCTION_NAME.match?(name)
        raise ArgumentError,
              'Function name must be DNS-safe: lowercase letters, numbers, and hyphens; 1-63 characters'
      end
      raise TypeError, 'Function payload must be a Hash' unless payload.is_a?(Hash)
    end

    def resolved_function_id(payload)
      function_id = payload['function_id'] if payload.is_a?(Hash)
      return function_id if function_id.is_a?(String) && !function_id.empty?

      raise TypeError, 'Expected a complete function response'
    end

    def function_response(response)
      version = header(response.headers, 'X-Volcano-Version')
      Transport.body(response, 200) unless response.status.between?(200, 299) || version

      FunctionResponse.new(
        data: response.body, status: response.status,
        headers: response.headers || {}, version: version
      )
    end

    def header(headers, name)
      headers&.find { |key, _| key.casecmp?(name) }&.last
    end
  end
end
