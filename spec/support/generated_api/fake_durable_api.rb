# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    # Records generated-client headers, identifiers, and list options.
    class FakeDurableApi
      attr_reader :calls

      def initialize
        @calls = []
      end

      def start_durable_execution_from_application_with_http_info(function_id, options = {})
        @calls << [:start, function_id, options]
        [FakeGeneratedModel.new(execution), 202, { 'X-Volcano-Version' => 'staging-v1' }]
      end

      def get_durable_execution_with_http_info(project_id, function_id, execution_id)
        @calls << [:get, project_id, function_id, execution_id]
        [FakeGeneratedModel.new(execution), 200, {}]
      end

      def list_durable_executions_with_http_info(project_id, function_id, options = {})
        @calls << [:list, project_id, function_id, options]
        page = { data: [execution], page: 2, limit: 5, total: 6, has_more: false }
        [FakeGeneratedModel.new(page), 200, {}]
      end

      def stop_durable_execution_with_http_info(project_id, function_id, execution_id)
        @calls << [:stop, project_id, function_id, execution_id]
        [FakeGeneratedModel.new(execution.merge(status: 'stopped')), 200, {}]
      end

      private

      def execution
        {
          id: '00000000-0000-4000-8000-000000000041',
          function_id: '00000000-0000-4000-8000-000000000042',
          name: 'charge-order-1',
          status: 'running',
          region: 'aws-us-east-1',
          created_at: '2026-01-01T00:00:00Z'
        }
      end
    end
  end
end
