# frozen_string_literal: true

require 'timeout'

module Volcano
  # Exposes the latest lease and reports asynchronous lease loss.
  class LockGuard
    EXPIRY_MESSAGE = 'lock lease expired before renewal completed'
    MAX_EXPIRY_POLL_SECONDS = 1.0
    UNSAFE_RENEWAL_MESSAGE = 'lock renewal returned no safe lease window'

    attr_reader :ttl

    def initialize(lease, ttl:, started_at:)
      @lease = lease
      @ttl = ttl
      @lease_clock = LockLeaseClock.new(ttl: ttl, started_at: started_at)
      @mutex = Mutex.new
      @changed = ConditionVariable.new
      @failure = nil
      @expiry_stopped = false
      @expiry_thread = nil
    end

    def lease = @mutex.synchronize { @lease }

    def lost?
      @mutex.synchronize do
        record_expiry_if_needed
        !@failure.nil?
      end
    end

    def wait_lost(timeout: nil) = @mutex.synchronize { wait_for_failure?(wait_deadline(timeout)) }

    def replace_lease(lease, started_at:)
      @mutex.synchronize do
        return false if @failure

        @lease = lease
        @lease_clock.reset(started_at)
        @changed.broadcast
        true
      end
    end

    def mark_lost(failure)
      @mutex.synchronize do
        @failure ||= failure
        @changed.broadcast
      end
    end

    def failure
      @mutex.synchronize do
        record_expiry_if_needed
        @failure
      end
    end

    def renewal_delay(delay) = @mutex.synchronize { delay.call(@ttl, remaining: remaining_time) }

    def start_expiry_watch
      @mutex.synchronize { @expiry_stopped = false }
      @expiry_thread = Thread.new { expiry_loop }
    end

    def stop_expiry_watch
      @mutex.synchronize do
        record_expiry_if_needed
        @expiry_stopped = true
        @changed.broadcast
      end
      @expiry_thread&.join
    end

    private

    def wait_for_failure?(deadline)
      loop do
        record_expiry_if_needed
        return true if @failure

        wait = wait_duration(deadline)
        return false unless wait

        @changed.wait(@mutex, wait)
      end
    end

    def wait_duration(deadline)
      return [expiry_delay, MAX_EXPIRY_POLL_SECONDS].min unless deadline

      caller_remaining = deadline - @lease_clock.monotonic_now
      return if caller_remaining <= 0

      [expiry_delay, caller_remaining, MAX_EXPIRY_POLL_SECONDS].min
    end

    def expiry_loop
      loop do
        state = @mutex.synchronize { expiry_step }
        break if state == :finished
      end
    end

    def expiry_step
      return :finished if @expiry_stopped

      delay = expiry_delay
      return record_expiry if delay <= 0

      @changed.wait(@mutex, [delay, MAX_EXPIRY_POLL_SECONDS].min)
      :waiting
    end

    def expiry_delay = remaining_time

    def record_expiry
      @failure ||= Timeout::Error.new(EXPIRY_MESSAGE)
      @changed.broadcast
      :finished
    end

    def record_expiry_if_needed
      record_expiry if !@failure && remaining_time <= 0
    end

    def remaining_time = @lease_clock.remaining

    def wait_deadline(timeout)
      timeout && (@lease_clock.monotonic_now + timeout)
    end
  end
end
