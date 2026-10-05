# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeLogsApi
      attr_reader :calls

      def initialize
        @calls = []
      end

      def search_project_logs_with_http_info(project_id, request, options = {})
        @calls << [:search, project_id, request, options]
        result = {
          data: [
            {
              id: 'event-1', timestamp: '2026-09-02T12:00:00Z',
              body: { message: 'ready', values: [1, 2], count: 2 },
              resource: { type: 'function', id: 'function-1' }
            }
          ],
          limit: 25, has_more: false
        }
        [JSON.generate(result), 200, {}]
      end

      def get_project_log_activity_with_http_info(project_id, request, options = {})
        @calls << [:activity, project_id, request, options]
        [JSON.generate(data: [], total: 0), 200, {}]
      end
    end
  end
end
