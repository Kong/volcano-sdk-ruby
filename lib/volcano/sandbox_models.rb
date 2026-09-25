# frozen_string_literal: true

module Volcano
  # Command output preserves nonzero exit codes as data.
  SandboxCommandResult = Data.define(:stdout, :stderr, :exit_code, :timed_out, :stdout_truncated, :stderr_truncated)
  # One-shot output is returned after confirmed guest reclamation.
  SandboxExecutionResult = Data.define(:stdout, :stderr, :exit_code, :timed_out, :stdout_truncated,
                                       :stderr_truncated, :session_id, :region, :duration_ms)
  # A published preset and its available memory and regions.
  SandboxPreset = Data.define(:id, :memory_mb, :regions)
  # Expiring HTTP access credentials are redacted from inspection.
  class SandboxAccess
    def initialize(url:, token:, expires_at:)
      @values = { url: url.dup.freeze, token: token.dup.freeze, expires_at: expires_at.dup.freeze }.freeze
      freeze
    end

    def url = @values.fetch(:url)
    def token = @values.fetch(:token)
    def expires_at = @values.fetch(:expires_at)

    def inspect = "#<Volcano::SandboxAccess expires_at=#{expires_at.inspect}>"
  end
end
