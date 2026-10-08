# frozen_string_literal: true

module Volcano
  # Create isolated sessions or execute a command to completion.
  class Sandboxes
    include SandboxDeployments

    def initialize(client, transport)
      @requests = SandboxRequests.new(client, transport)
    end

    def presets
      response = @requests.call(SandboxRequest.new(operation: :list_sandbox_presets))
      SandboxResponse.array(Transport.json_object(response)['data']).map { |value| SandboxResponse.preset(value) }
    end

    def inspect = '#<Volcano::Sandboxes>'

    def create( # rubocop:disable Metrics/ParameterLists -- Preserve explicit typed facade keywords.
      project_id, region:, preset: nil, sandbox_id: nil, memory_mb: nil,
      max_duration_seconds: nil, idle_timeout_seconds: nil, request_id: nil
    )
      options = { region: region, preset: preset, sandbox_id: sandbox_id, memory_mb: memory_mb,
                  max_duration_seconds: max_duration_seconds, idle_timeout_seconds: idle_timeout_seconds,
                  request_id: request_id }.compact
      body = SandboxRequests.selector(options).merge(options.slice(:max_duration_seconds, :idle_timeout_seconds))
      request = SandboxRequest.new(operation: :create_sandbox_session,
                                   resource_id: SandboxRequests.identifier(project_id), body: body,
                                   request_id: SandboxRequests.request_id(options))
      requests = @requests.service_scope
      SandboxSession.new(requests, requests.call(request, status: 201))
    end

    def get(session_id)
      request = SandboxRequest.new(operation: :get_sandbox_session, resource_id: SandboxRequests.identifier(session_id))
      SandboxSession.new(@requests, @requests.call(request))
    end

    def exec( # rubocop:disable Metrics/ParameterLists -- Preserve explicit typed facade keywords.
      project_id, command, region:, preset: nil, sandbox_id: nil, memory_mb: nil,
      timeout_seconds: 60, environment: nil, request_id: nil
    )
      options = { region: region, preset: preset, sandbox_id: sandbox_id, memory_mb: memory_mb,
                  timeout_seconds: timeout_seconds, environment: environment, request_id: request_id }.compact
      body = SandboxRequests.selector(options).merge(SandboxRequests.command(command, options))
      request = SandboxRequest.new(operation: :execute_sandbox, resource_id: SandboxRequests.identifier(project_id),
                                   body: body, request_id: SandboxRequests.request_id(options),
                                   timeout: SandboxResponse.integer(options.fetch(:timeout_seconds, 60)) + 120)
      SandboxResponse.execution(@requests.call(request))
    end

    def grant(session_id, auth_user_id, expires_at:)
      request = SandboxRequest.new(operation: :grant_sandbox_session,
                                   resource_id: SandboxRequests.identifier(session_id),
                                   subject_id: SandboxRequests.identifier(auth_user_id),
                                   body: { expires_at: SandboxRequests.expiry(expires_at) })
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
