# frozen_string_literal: true

module Volcano
  # Dispatch only the generated operations exposed by the Sandbox facade.
  class GeneratedTransport
    SANDBOX_OPERATIONS = {
      list_sandbox_presets: lambda { |api, _request|
        api.list_sandbox_presets_with_http_info(debug_return_type: 'Object')
      },
      create_sandbox_session: lambda { |api, request|
        api.create_sandbox_session_with_http_info(request.resource_id, request.request_id, request.body,
                                                  debug_return_type: 'Object')
      },
      execute_sandbox: lambda { |api, request|
        api.execute_sandbox_with_http_info(request.resource_id, request.request_id, request.body,
                                           debug_return_type: 'Object')
      },
      get_sandbox_session: lambda { |api, request|
        api.get_sandbox_session_with_http_info(request.resource_id, debug_return_type: 'Object')
      },
      execute_sandbox_session: lambda { |api, request|
        api.execute_sandbox_session_with_http_info(request.resource_id, request.request_id, request.body,
                                                   debug_return_type: 'Object')
      },
      suspend_sandbox_session: lambda { |api, request|
        api.suspend_sandbox_session_with_http_info(request.resource_id, debug_return_type: 'Object')
      },
      resume_sandbox_session: lambda { |api, request|
        api.resume_sandbox_session_with_http_info(request.resource_id, debug_return_type: 'Object')
      },
      terminate_sandbox_session: lambda { |api, request|
        api.terminate_sandbox_session_with_http_info(request.resource_id, debug_return_type: 'Object')
      },
      create_sandbox_session_access: lambda { |api, request|
        api.create_sandbox_session_access_with_http_info(request.resource_id, request.body, debug_return_type: 'Object')
      },
      read_sandbox_session_file: lambda { |api, request|
        api.read_sandbox_session_file_with_http_info(request.resource_id, request.body, debug_return_type: 'Object')
      },
      write_sandbox_session_file: lambda { |api, request|
        api.write_sandbox_session_file_with_http_info(request.resource_id, request.body, debug_return_type: 'Object')
      },
      grant_sandbox_session: lambda { |api, request|
        api.grant_sandbox_session_with_http_info(request.resource_id, request.subject_id, request.body,
                                                 debug_return_type: 'Object')
      },
      revoke_sandbox_session: lambda { |api, request|
        api.revoke_sandbox_session_with_http_info(request.resource_id, request.subject_id, debug_return_type: 'Object')
      }
    }.freeze
    private_constant :SANDBOX_OPERATIONS

    def sandbox_request(authorization:, request:)
      invoke do
        api = sandbox_api(authorization, request.timeout)
        data, status, headers = SANDBOX_OPERATIONS.fetch(request.operation).call(api, request)
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
