# frozen_string_literal: true

module Volcano
  # Validate custom-image deployment responses before exposing typed values.
  module SandboxDeploymentResponse
    def self.deployment(value)
      data = Transport.json_object(value)
      SandboxDeployment.new(id: SandboxResponse.text(data['id']), status: SandboxResponse.text(data['status']),
                            created_at: SandboxResponse.text(data['created_at']),
                            updated_at: SandboxResponse.text(data['updated_at']))
    end

    def self.page(value)
      data = Transport.json_object(value)
      pagination = Transport.json_object(data['pagination'])
      SandboxDeploymentPage.new(data: SandboxResponse.array(data['data']).map { |row| deployment(row) }.freeze,
                                limit: SandboxResponse.integer(pagination['limit']),
                                has_more: SandboxResponse.flag(pagination['has_more']),
                                next_cursor: optional_text(pagination['next_cursor']))
    end

    def self.logs(value)
      data = Transport.json_object(value)
      SandboxBuildLogPage.new(data: SandboxResponse.array(data['data']).map { |row| log(row) }.freeze,
                              next_cursor: optional_text(data['next_cursor']))
    end

    def self.log(value)
      data = Transport.json_object(value)
      SandboxBuildLog.new(timestamp: SandboxResponse.text(data['timestamp']),
                          message: SandboxResponse.text(data['message']))
    end

    def self.optional_text(value)
      value.nil? ? nil : SandboxResponse.text(value)
    end
    private_class_method :log, :optional_text
  end
end
