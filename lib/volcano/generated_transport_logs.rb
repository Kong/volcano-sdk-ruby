# frozen_string_literal: true

module Volcano
  class GeneratedTransport
    # Generated OpenAPI operations used by the public logs facade.
    module LogTransport
      def search_project_logs(authorization:, project_id:, request:)
        invoke do
          apis = @api_factory.call(authorization)
          body = Generated::LogSearchRequest.new(deep_symbolize(request))
          data, status, headers = apis.logs.search_project_logs_with_http_info(
            project_id, body, debug_return_type: 'String'
          )
          response(parse_body(data), status, headers)
        end
      end

      def get_project_log_activity(authorization:, project_id:, request:)
        invoke do
          apis = @api_factory.call(authorization)
          body = Generated::LogActivityRequest.new(deep_symbolize(request))
          data, status, headers = apis.logs.get_project_log_activity_with_http_info(
            project_id, body, debug_return_type: 'String'
          )
          response(parse_body(data), status, headers)
        end
      end
    end
    private_constant :LogTransport
  end
end
