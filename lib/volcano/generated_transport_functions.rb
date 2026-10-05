# frozen_string_literal: true

module Volcano
  # Preserves function-owned response bodies through the generated transport.
  class GeneratedTransport
    def resolve_function_for_invocation(authorization:, name:)
      invoke do
        apis = @api_factory.call(authorization)
        # Read the resolve body as JSON rather than the generated model: the
        # model drops fields the vendored specification predates, and
        # invoke_url is one of them.
        data, status, headers = apis.functions.resolve_function_for_invocation_with_http_info(
          name, debug_return_type: 'String'
        )
        response(resolve_body(data), status, headers)
      end
    end

    def invoke_function(authorization:, function_id:, payload:)
      invoke do
        data, status, headers = function_http_response(authorization, function_id, payload)
        response(function_body(data, headers), status, headers)
      end
    end

    def invoke_function_url(authorization:, invoke_url:, payload:)
      invoke do
        data, status, headers = function_url_response(authorization, invoke_url, payload)
        response(function_body(data, headers), status, headers)
      end
    end

    private

    def resolve_body(body)
      return body unless body.is_a?(String)
      return nil if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    # The resolved endpoint is absolute and off the API host, so it cannot go
    # through the generated client's configured base URL. The body still uses
    # the invoke contract's { payload } envelope.
    def function_url_response(authorization, invoke_url, payload)
      request = Typhoeus::Request.new(
        invoke_url,
        method: :post,
        body: JSON.generate(payload: payload),
        headers: {
          'Authorization' => "Bearer #{authorization}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        },
        timeout: @timeout,
        followlocation: false
      )
      result = request.run
      raise Error::TransportError, (result.return_message || 'Volcano request failed') unless result.code.positive?

      [result.body, result.code, result.headers || {}]
    end

    def function_http_response(authorization, function_id, payload)
      apis = @api_factory.call(authorization)
      request = Generated::FunctionInvocationRequest.new(payload: payload)
      apis.functions.invoke_function_with_http_info(
        function_id, request, follow_location: false, debug_return_type: 'String'
      )
    rescue Generated::ApiError => e
      status = error_status(e)
      raise if status.zero?

      [e.response_body, status, e.response_headers || {}]
    end

    def function_body(body, headers)
      text = normalized_function_text(body)
      return nil if text.nil? || text.empty?
      return text unless function_json?(text, headers)

      parse_function_json(text)
    end

    def normalized_function_text(body)
      raise TypeError, 'Expected a string function response' unless body.nil? || body.is_a?(String)

      return nil if body.nil? || body.empty?

      body.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix("\uFEFF")
    end

    def parse_function_json(text)
      parsed = JSON.parse(text)
      valid_function_encoding?(parsed) ? parsed : text
    rescue JSON::ParserError
      text
    end

    def valid_function_encoding?(value)
      case value
      when Hash then valid_function_hash_encoding?(value)
      when Array then value.all? { |item| valid_function_encoding?(item) }
      when String then value.valid_encoding?
      else true
      end
    end

    def valid_function_hash_encoding?(value)
      value.all? { |key, item| valid_function_encoding?(key) && valid_function_encoding?(item) }
    end

    def function_json?(text, headers)
      return true if text.start_with?('{', '[')

      headers.to_h.any? do |key, value|
        key.casecmp?('Content-Type') && value.to_s.downcase.include?('application/json')
      end
    end
  end
end
