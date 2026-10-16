# frozen_string_literal: true

module Volcano
  # Durable message operations for the internal generated transport. A target
  # with a project id takes the owner's project route; one without takes the
  # application route, with the execution's client token when there is one.
  class GeneratedTransport
    def send_durable_message(authorization:, target:, name:, data:, idempotency_key:)
      invoke do
        durable = @api_factory.call(authorization).durable
        body = Generated::SendDurableMessageRequest.new(name: name, data: data)
        payload, status, headers = send_on_route(durable, target, body, idempotency_key)
        response(payload, status, headers)
      end
    end

    def list_durable_messages(authorization:, target:, query:)
      invoke do
        data, status, headers = list_on_route(@api_factory.call(authorization).durable, target, query)
        response(data, status, headers)
      end
    end

    private

    def send_on_route(durable, target, body, idempotency_key)
      if target.project_id
        durable.send_durable_message_with_http_info(
          target.project_id, target.function_id, target.execution_id, body,
          durable_message_options(idempotency_key: idempotency_key)
        )
      else
        durable.send_durable_message_from_application_with_http_info(
          target.function_id, target.execution_id, body,
          durable_message_options(idempotency_key: idempotency_key, x_volcano_client_token: target.client_token)
        )
      end
    end

    def list_on_route(durable, target, query)
      if target.project_id
        durable.list_durable_messages_with_http_info(
          target.project_id, target.function_id, target.execution_id, durable_message_options(**query)
        )
      else
        durable.list_durable_messages_from_application_with_http_info(
          target.function_id, target.execution_id,
          durable_message_options(**query, x_volcano_client_token: target.client_token)
        )
      end
    end

    def durable_message_options(**options)
      options.compact.merge(debug_return_type: 'Object')
    end
  end
end
