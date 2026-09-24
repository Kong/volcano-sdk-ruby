# frozen_string_literal: true

module Volcano
  # A session handle whose observed state changes only after validated responses.
  class SandboxSession
    attr_reader :id, :project_id, :region, :state, :expires_at, :files

    def initialize(requests, value)
      data = Transport.json_object(value)
      @requests = requests
      @id = SandboxRequests.identifier(data['id'])
      @project_id = SandboxRequests.identifier(data['project_id'])
      @region = SandboxResponse.text(data['region'])
      assign_state(data)
      @files = SandboxFiles.new(requests, @id)
    end

    def refresh = update(:get_sandbox_session)
    def suspend = update(:suspend_sandbox_session, status: 202)
    def resume = update(:resume_sandbox_session, status: 202)
    def terminate = update(:terminate_sandbox_session, status: 202)

    def exec(command, options = {})
      request = SandboxRequest.new(operation: :execute_sandbox_session, resource_id: @id,
                                   body: SandboxRequests.command(command, options),
                                   request_id: SandboxRequests.request_id(options),
                                   timeout: SandboxResponse.integer(options.fetch(:timeout_seconds, 60)) + 120)
      SandboxResponse.command(@requests.call(request))
    end

    def access(port)
      request = SandboxRequest.new(operation: :create_sandbox_session_access, resource_id: @id, body: { port: port })
      SandboxResponse.access(@requests.call(request))
    end

    def use
      yield self
    ensure
      terminate unless @state == 'terminated'
    end

    private

    def update(operation, status: 200)
      response = @requests.call(SandboxRequest.new(operation: operation, resource_id: @id), status: status)
      data = Transport.json_object(response)
      raise TypeError, 'Sandbox session identity changed' unless data['id'] == @id

      assign_state(data)
      self
    end

    def assign_state(data)
      next_state = SandboxResponse.state(data['state'])
      expiry = SandboxResponse.text(data['expires_at'])
      @state = next_state
      @expires_at = expiry
    end
  end
end
