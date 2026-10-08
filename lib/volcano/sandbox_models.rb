# frozen_string_literal: true

module Volcano
  # Command output preserves nonzero exit codes as data.
  SandboxCommandResult = Data.define(:stdout, :stderr, :exit_code, :timed_out, :stdout_truncated, :stderr_truncated)
  # One-shot output is returned after confirmed guest reclamation.
  SandboxExecutionResult = Data.define(:stdout, :stderr, :exit_code, :timed_out, :stdout_truncated,
                                       :stderr_truncated, :session_id, :region, :duration_ms)
  # A published preset and its available memory and regions.
  SandboxPreset = Data.define(:id, :memory_mb, :regions)
  # Immutable build status for a custom template version.
  SandboxDeployment = Data.define(:id, :status, :created_at, :updated_at)
  # A page of custom template versions.
  SandboxDeploymentPage = Data.define(:data, :limit, :has_more, :next_cursor)
  # One regional build message.
  SandboxBuildLog = Data.define(:timestamp, :message)
  # A page of regional build output.
  SandboxBuildLogPage = Data.define(:data, :next_cursor)
  # Expiring HTTP access credentials are redacted from inspection.
  class SandboxAccess
    attr_reader :url, :token, :expires_at

    def initialize(url:, token:, expires_at:)
      @url = url.dup.freeze
      @token = token.dup.freeze
      @expires_at = expires_at.dup.freeze
      freeze
    end

    def inspect = "#<Volcano::SandboxAccess expires_at=#{expires_at.inspect}>"
  end
end
