# frozen_string_literal: true

module Volcano
  # Sandbox operations use generated paths and normal typed error conversion.
  class GeneratedTransport
    def sandbox_request(authorization:, request:)
      invoke do
        api = sandbox_api(authorization, request.timeout)
        arguments = [request.resource_id, request.subject_id, request.request_id, request.body].compact
        result = api.public_send("#{request.operation}_with_http_info", *arguments, debug_return_type: 'Object')
        data, status, headers = result
        response(data, status, headers)
      end
    end

    private

    def sandbox_api(authorization, timeout)
      configuration = generated_configuration(authorization)
      configuration.timeout = [configuration.timeout, (timeout * 1_000).round].max
      Generated::SandboxesApi.new(ApiClient.new(configuration))
    end
  end
end
