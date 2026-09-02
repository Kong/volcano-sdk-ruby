# frozen_string_literal: true

module Volcano
  # Renews one guarded lease until its block exits or ownership is lost.
  class LockRenewer
    Config = Data.define(:ttl, :delay, :shutdown_timeout)

    def initialize(locks, key, guard, config)
      @locks = locks
      @key = key
      @guard = guard
      @config = config
      @mutex = Mutex.new
      @stopped = ConditionVariable.new
      @stop = false
      @thread = nil
    end

    def start
      @thread = Thread.new { renewal_loop }
    end

    def stop
      request_stop
      return unless @thread

      # Renew requires current token ownership, so a late request cannot resurrect a released lease.
      @thread.join(@config.shutdown_timeout)
    end

    private

    def renewal_loop
      loop do
        return if @guard.lost?
        return if wait_to_renew
        return if @guard.lost?

        renew
      end
    end

    def wait_to_renew
      seconds = @guard.renewal_delay(@config.delay)
      @mutex.synchronize do
        @stopped.wait(@mutex, seconds) unless @stop
        @stop
      end
    end

    def renew
      started_at = LockLeaseClock.now
      lease = @locks.renew(@key, @guard.lease, ttl: @config.ttl)
      replaced = @guard.replace_lease(lease, started_at: started_at)
      return if replaced && renewal_safe?

      @guard.mark_lost(Timeout::Error.new(LockGuard::UNSAFE_RENEWAL_MESSAGE))
    rescue StandardError => e
      @guard.mark_lost(e)
    end

    def renewal_safe?
      @guard.renewal_delay(@config.delay).positive?
    end

    def request_stop
      @mutex.synchronize do
        @stop = true
        @stopped.broadcast
      end
    end
  end
end
