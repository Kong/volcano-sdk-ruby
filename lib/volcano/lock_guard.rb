# frozen_string_literal: true

require 'timeout'

module Volcano
  # Exposes the latest lease and reports asynchronous lease loss.
  class LockGuard
    EXPIRY_MESSAGE = 'lock lease expired before renewal completed'
    UNSAFE_RENEWAL_MESSAGE = 'lock renewal returned no safe lease window'

    attr_reader :ttl

    def initialize(lease, ttl:, started_at:)
      @lease = lease
      @ttl = ttl
      @lease_deadline = lease_deadline(lease, started_at)
      @mutex = Mutex.new
      @changed = ConditionVariable.new
      @failure = nil
      @expiry_stopped = false
      @expiry_thread = nil
    end

    def lease
      @mutex.synchronize { @lease }
    end

    def lost?
      @mutex.synchronize { !@failure.nil? }
    end

    def wait_lost(timeout: nil)
      deadline = timeout && (monotonic_now + timeout)
      @mutex.synchronize { wait_for_failure?(deadline) }
    end

    def replace_lease(lease, started_at:)
      @mutex.synchronize do
        return false if @failure

        @lease = lease
        @lease_deadline = lease_deadline(lease, started_at)
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
      @mutex.synchronize { @failure }
    end

    def renewal_delay(delay)
      @mutex.synchronize do
        delay.call(@ttl, @lease, deadline: @lease_deadline)
      end
    end

    def start_expiry_watch
      @mutex.synchronize { @expiry_stopped = false }
      @expiry_thread = Thread.new { expiry_loop }
    end

    def stop_expiry_watch
      @mutex.synchronize do
        record_expiry if monotonic_now >= @lease_deadline && !@failure
        @expiry_stopped = true
        @changed.broadcast
      end
      @expiry_thread&.join
    end

    private

    def wait_for_failure?(deadline)
      until @failure
        remaining = deadline && (deadline - monotonic_now)
        break if remaining&.<=(0)

        @changed.wait(@mutex, remaining)
      end
      !@failure.nil?
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

      @changed.wait(@mutex, delay)
      :waiting
    end

    def expiry_delay
      [0.0, @lease_deadline - monotonic_now].max
    end

    def record_expiry
      @failure ||= Timeout::Error.new(EXPIRY_MESSAGE)
      @changed.broadcast
      :finished
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def lease_deadline(lease, started_at)
      request_deadline = started_at + ttl
      return request_deadline unless lease.expires_at

      wall_remaining = [0.0, lease.expires_at - Time.now].max
      [request_deadline, monotonic_now + wall_remaining].min
    end
  end
end
