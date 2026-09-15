# frozen_string_literal: true

module Volcano
  # Durable execution operations for the internal generated transport.
  class GeneratedTransport
    def start_durable_execution_from_application(
      authorization:, function_id:, payload:, execution_name: nil
    )
      invoke do
        apis = @api_factory.call(authorization)
        options = { body: payload, x_volcano_execution_name: execution_name }.compact
        result = apis.durable.start_durable_execution_from_application_with_http_info(
          function_id, options
        )
        data, status, headers = result
        response(data, status, headers)
      end
    end

    def get_durable_execution(authorization:, project_id:, function_id:, execution_id:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.durable.get_durable_execution_with_http_info(
          project_id, function_id, execution_id
        )
        response(data, status, headers)
      end
    end

    def list_durable_executions(authorization:, project_id:, function_id:, options:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.durable.list_durable_executions_with_http_info(
          project_id, function_id, options
        )
        response(data, status, headers)
      end
    end

    def stop_durable_execution(authorization:, project_id:, function_id:, execution_id:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.durable.stop_durable_execution_with_http_info(
          project_id, function_id, execution_id
        )
        response(data, status, headers)
      end
    end
  end
end
