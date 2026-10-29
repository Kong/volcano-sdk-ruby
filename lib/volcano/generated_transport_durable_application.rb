# frozen_string_literal: true

module Volcano
  # Durable execution reads and stops on the application route, which take the
  # credential a start takes and, where it needs one, the execution's client
  # token.
  class GeneratedTransport
    def get_durable_execution_from_application(authorization:, function_id:, execution_id:, client_token:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.durable.get_durable_execution_from_application_with_http_info(
          function_id, execution_id, { x_volcano_client_token: client_token }.compact
        )
        response(data, status, headers)
      end
    end

    def stop_durable_execution_from_application(authorization:, function_id:, execution_id:, client_token:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.durable.stop_durable_execution_from_application_with_http_info(
          function_id, execution_id, { x_volcano_client_token: client_token }.compact
        )
        response(data, status, headers)
      end
    end
  end
end
