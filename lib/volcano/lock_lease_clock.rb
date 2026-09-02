# frozen_string_literal: true

module Volcano
  # Tracks lease age across wall-clock changes and host suspension.
  class LockLeaseClock
    MAX_LEASE_LIFETIME_SECONDS = 7_776_000
    SUSPEND_AWARE = Process.const_defined?(:CLOCK_BOOTTIME)
    CLOCK_ID = SUSPEND_AWARE ? Process.const_get(:CLOCK_BOOTTIME) : Process::CLOCK_MONOTONIC
    Timestamp = Data.define(:monotonic, :wall)

    def self.now = Process.clock_gettime(CLOCK_ID)
    def self.capture = Timestamp.new(monotonic: now, wall: Time.now)
    def self.suspend_aware? = SUSPEND_AWARE

    def initialize(ttl:, started_at:)
      @ttl = ttl
      @absolute_deadline = started_at.monotonic + MAX_LEASE_LIFETIME_SECONDS
      @absolute_wall_deadline = started_at.wall + MAX_LEASE_LIFETIME_SECONDS
      reset(started_at)
    end

    def reset(started_at)
      @deadline = [started_at.monotonic + @ttl, @absolute_deadline].min
      @wall_deadline = [started_at.wall + @ttl, @absolute_wall_deadline].min
    end

    def remaining
      monotonic_remaining = @deadline - monotonic_now
      remaining = if self.class.suspend_aware?
                    monotonic_remaining
                  else
                    [monotonic_remaining, @wall_deadline - Time.now].min
                  end
      remaining.clamp(0.0, Float::INFINITY)
    end

    def monotonic_now = self.class.now
  end
end
