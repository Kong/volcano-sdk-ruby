# frozen_string_literal: true

module Volcano
  # Tracks lease age across wall-clock changes and host suspension.
  class LockLeaseClock
    def initialize(ttl:, started_at:, wall_started_at:)
      @ttl = ttl
      reset(started_at, wall_started_at)
    end

    def reset(started_at, wall_started_at)
      @monotonic_deadline = started_at + @ttl
      @wall_deadline = wall_started_at + @ttl
    end

    def remaining
      monotonic_remaining = @monotonic_deadline - monotonic_now
      wall_remaining = @wall_deadline - Time.now
      [monotonic_remaining, wall_remaining].min.clamp(0.0, Float::INFINITY)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
