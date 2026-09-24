# frozen_string_literal: true

module Volcano
  # Validate wire values before exposing language-native Sandbox results.
  module SandboxResponse
    STATES = %w[starting running suspending suspended resuming terminating terminated unknown].freeze
    private_constant :STATES

    def self.text(value)
      return value if value.is_a?(String)

      raise TypeError, 'Invalid Sandbox text field'
    end

    def self.integer(value)
      return value if value.is_a?(Integer)

      raise TypeError, 'Invalid Sandbox integer field'
    end

    def self.flag(value)
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      raise TypeError, 'Invalid Sandbox flag'
    end

    def self.state(value)
      result = text(value)
      return result if STATES.include?(result)

      raise TypeError, 'Invalid Sandbox state'
    end

    def self.command(value)
      data = Transport.json_object(value)
      SandboxCommandResult.new(
        stdout: text(data['stdout']), stderr: text(data['stderr']), exit_code: integer(data['exit_code']),
        timed_out: flag(data['timed_out']), stdout_truncated: flag(data['stdout_truncated']),
        stderr_truncated: flag(data['stderr_truncated'])
      )
    end

    def self.execution(value)
      data = Transport.json_object(value)
      SandboxExecutionResult.new(
        **command(data).to_h, session_id: text(data['session_id']),
                              region: text(data['region']), duration_ms: integer(data['duration_ms'])
      )
    end

    def self.access(value)
      data = Transport.json_object(value)
      SandboxAccess.new(url: text(data['url']), token: text(data['token']), expires_at: text(data['expires_at']))
    end

    def self.preset(value)
      data = Transport.json_object(value)
      regions = array(data['regions']).map { |region| text(region) }.freeze
      SandboxPreset.new(id: text(data['id']), memory_mb: integer(data['memory_mb']), regions: regions)
    end

    def self.array(value)
      return value if value.is_a?(Array)

      raise TypeError, 'Invalid Sandbox list'
    end
  end
end
