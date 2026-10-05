# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeFunctionsApi
      attr_reader :calls

      def initialize
        @calls = []
      end

      def resolve_function_for_invocation_with_http_info(name, options = {})
        @calls << [:resolve, name, options]
        body = JSON.generate(
          name: name,
          function_id: '00000000-0000-4000-8000-000000000040',
          cache_ttl_seconds: 60
        )
        [body, 200, {}]
      end

      def invoke_function_with_http_info(function_id, request, options = {})
        @calls << [:invoke, function_id, request, options]
        [
          JSON.generate(error: 'invalid order'),
          422,
          { 'X-Volcano-Version' => 'staging-v1' }
        ]
      end
    end
  end
end
