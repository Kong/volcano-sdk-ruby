# frozen_string_literal: true

module Volcano
  # Build, inspect, and export custom templates from source archives.
  module SandboxDeployments
    def deploy( # rubocop:disable Metrics/ParameterLists -- Preserve explicit typed facade keywords.
      project_id, sandbox_id, source, name:, memory_mb: 1024, ports: [], request_id: nil
    )
      validate_source(source, ports)
      # @type var options: sandbox_request_options
      options = { operation: :deploy_sandbox, archive: source.dup.freeze,
                  body: { name: name, memory_mb: memory_mb, ports: ports },
                  request_id: SandboxRequests.request_id({ request_id: request_id }.compact) }
      request = deployment_request(project_id, sandbox_id, options)
      SandboxDeploymentResponse.deployment(@requests.service_scope.call(request, status: 202))
    end

    def deployments(project_id, sandbox_id, cursor: nil)
      request = deployment_request(project_id, sandbox_id,
                                   { operation: :list_sandbox_deployments, cursor: cursor })
      SandboxDeploymentResponse.page(@requests.service_scope.call(request))
    end

    def deployment(project_id, sandbox_id, deployment_id)
      request = deployment_request(project_id, sandbox_id, operation: :get_sandbox_deployment,
                                                           deployment_id: SandboxRequests.identifier(deployment_id))
      SandboxDeploymentResponse.deployment(@requests.service_scope.call(request))
    end

    def source(project_id, sandbox_id, deployment_id)
      request = deployment_request(project_id, sandbox_id, operation: :get_sandbox_deployment_source,
                                                           deployment_id: SandboxRequests.identifier(deployment_id))
      SandboxResponse.text(@requests.service_scope.call(request)).b
    end

    def logs( # rubocop:disable Metrics/ParameterLists -- Preserve explicit typed facade keywords.
      project_id, sandbox_id, deployment_id, region:, cursor: nil, limit: 100
    )
      # @type var options: sandbox_request_options
      options = { operation: :get_sandbox_deployment_logs, deployment_id: SandboxRequests.identifier(deployment_id),
                  region: region, cursor: cursor, limit: limit }
      SandboxDeploymentResponse.logs(@requests.service_scope.call(deployment_request(project_id, sandbox_id, options)))
    end

    def delete_template(project_id, sandbox_id)
      @requests.service_scope.call(deployment_request(project_id, sandbox_id, operation: :delete_sandbox), status: 202)
      nil
    end

    private

    def deployment_request(project_id, sandbox_id, options)
      options[:resource_id] = SandboxRequests.identifier(project_id)
      options[:subject_id] = SandboxRequests.identifier(sandbox_id)
      SandboxRequest.new(options)
    end

    def validate_source(source, ports)
      if source.bytesize > 32 * 1024 * 1024
        raise Error::ValidationError, 'Sandbox source archives are limited to 32 MiB'
      end
      return if ports.all? { |port| port.between?(1, 65_535) }

      raise Error::ValidationError, 'Sandbox ports must be between 1 and 65535'
    end
  end
end
