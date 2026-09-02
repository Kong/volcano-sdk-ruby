# frozen_string_literal: true

require 'English'

module Volcano
  # Owns renewal and cleanup for one block-scoped lock lease.
  class LockSession
    def initialize(locks, key, guard, renewer, delay)
      @locks = locks
      @key = key
      @guard = guard
      @renewer = renewer
      @delay = delay
      @renewer_started = false
    end

    def run
      prepare
      start
      yield @guard
    ensure
      cleanup($ERROR_INFO.nil?)
    end

    private

    def prepare
      return unless @guard.renewal_delay(@delay).zero?

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wall_started_at = Time.now
      lease = @locks.renew(@key, @guard.lease, ttl: @guard.ttl)
      replaced = @guard.replace_lease(
        lease, started_at: started_at, wall_started_at: wall_started_at
      )
      return if replaced && @guard.renewal_delay(@delay).positive?

      failure = Timeout::Error.new(LockGuard::UNSAFE_RENEWAL_MESSAGE)
      @guard.mark_lost(failure)
      raise failure
    end

    def start
      @guard.start_expiry_watch
      @renewer.start
      @renewer_started = true
    end

    def cleanup(completed)
      @renewer.stop if @renewer_started
    ensure
      @guard.stop_expiry_watch
      finish(completed)
    end

    def finish(completed)
      release_error = release_safely
      return unless completed

      raise @guard.failure if @guard.failure
      raise release_error if release_error
    end

    def release_safely
      @locks.release(@key, @guard.lease)
      nil
    rescue StandardError => e
      e
    end
  end
end
