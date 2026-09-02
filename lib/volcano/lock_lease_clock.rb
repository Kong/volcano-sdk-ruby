# frozen_string_literal: true

module Volcano
  # Tracks lease age across wall-clock changes and host suspension.
  class LockLeaseClock
    MAX_LEASE_LIFETIME_SECONDS = 7_776_000
    CLOCK_ID = if Process.const_defined?(:CLOCK_BOOTTIME)
                 Process.const_get(:CLOCK_BOOTTIME)
               else
                 Process::CLOCK_MONOTONIC
               end

    def self.now = Process.clock_gettime(CLOCK_ID)

    def initialize(ttl:, started_at:)
      @ttl = ttl
      @absolute_deadline = started_at + MAX_LEASE_LIFETIME_SECONDS
      reset(started_at)
    end

    def reset(started_at)
      @deadline = [started_at + @ttl, @absolute_deadline].min
    end

    def remaining = (@deadline - monotonic_now).clamp(0.0, Float::INFINITY)

    def monotonic_now = self.class.now
  end
end
