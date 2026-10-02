# frozen_string_literal: true

module Volcano
  # Create isolated sessions or execute a command to completion.
  class Sandboxes
    def initialize(client, transport)
      @requests = SandboxRequests.new(client, transport)
    end

    def presets
      response = @requests.call(SandboxRequest.new(operation: :list_sandbox_presets))
      SandboxResponse.array(Transport.json_object(response)['data']).map { |value| SandboxResponse.preset(value) }
    end

    def create(project_id, options)
      body = SandboxRequests.selector(options).merge(options.slice(:max_duration_seconds, :idle_timeout_seconds))
      request = SandboxRequest.new(operation: :create_sandbox_session,
                                   resource_id: SandboxRequests.identifier(project_id), body: body,
                                   request_id: SandboxRequests.request_id(options))
      SandboxSession.new(@requests, @requests.call(request, status: 201))
    end

    def get(session_id)
      request = SandboxRequest.new(operation: :get_sandbox_session, resource_id: SandboxRequests.identifier(session_id))
      SandboxSession.new(@requests, @requests.call(request))
    end

    def exec(project_id, command, options)
      body = SandboxRequests.selector(options).merge(SandboxRequests.command(command, options))
      request = SandboxRequest.new(operation: :execute_sandbox, resource_id: SandboxRequests.identifier(project_id),
                                   body: body, request_id: SandboxRequests.request_id(options))
      SandboxResponse.execution(@requests.call(request))
    end

    def grant(session_id, auth_user_id, expires_at:)
      request = SandboxRequest.new(operation: :grant_sandbox_session,
                                   resource_id: SandboxRequests.identifier(session_id),
                                   subject_id: SandboxRequests.identifier(auth_user_id),
                                   body: { expires_at: expires_at })
      @requests.call(request, status: 204)
      nil
    end

    def revoke(session_id, auth_user_id)
      request = SandboxRequest.new(operation: :revoke_sandbox_session,
                                   resource_id: SandboxRequests.identifier(session_id),
                                   subject_id: SandboxRequests.identifier(auth_user_id))
      @requests.call(request, status: 204)
      nil
    end
  end
end
