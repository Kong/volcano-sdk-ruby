# frozen_string_literal: true

module Volcano
  # Preserves function-owned response bodies through the generated transport.
  class GeneratedTransport
    def resolve_function_for_invocation(authorization:, name:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.functions.resolve_function_for_invocation_with_http_info(name)
        response(data, status, headers)
      end
    end

    def invoke_function(authorization:, function_id:, payload:)
      invoke do
        data, status, headers = function_http_response(authorization, function_id, payload)
        response(function_body(data, headers), status, headers)
      end
    end

    private

    def function_http_response(authorization, function_id, payload)
      apis = @api_factory.call(authorization)
      request = Generated::FunctionInvocationRequest.new(payload: payload)
      apis.functions.invoke_function_with_http_info(
        function_id, request, follow_location: false, debug_return_type: 'String'
      )
    rescue Generated::ApiError => e
      raise if e.code.to_i.zero?

      [e.response_body, e.code.to_i, e.response_headers || {}]
    end

    def function_body(body, headers)
      return nil if body.nil? || body.empty?

      text = body.dup.force_encoding(Encoding::UTF_8).scrub
      return text unless function_json?(text, headers)

      JSON.parse(text)
    rescue JSON::ParserError
      text
    end

    def function_json?(text, headers)
      return true if text.start_with?('{', '[')

      headers.to_h.any? do |key, value|
        key.casecmp?('Content-Type') && value.to_s.downcase.include?('application/json')
      end
    end
  end
end
