# frozen_string_literal: true

module Volcano
  # Adds block-scoped automatic renewal to the lock facade.
  module LockAutoRenewal
    MIN_LOCK_TTL_SECONDS = 5
    MAX_LOCK_TTL_SECONDS = 7_776_000
    MAX_RENEWAL_DELAY_SECONDS = 60.0
    RENEWAL_SAFETY_MARGIN_SECONDS = 1.0
    RENEWAL_REQUEST_BUDGET_SECONDS = 1.0
    RENEWER_SHUTDOWN_TIMEOUT_SECONDS = 1.0

    def with_lock(key, ttl:, &)
      validate_ttl(ttl)
      started_at = LockLeaseClock.now
      guard = LockGuard.new(acquire(key, ttl: ttl), ttl: ttl, started_at: started_at)
      renewer = lock_renewer(key, guard, ttl)
      LockSession.new(self, key, guard, renewer, method(:renewal_delay)).run(&)
    end

    private

    def lock_renewer(key, guard, ttl)
      config = LockRenewer::Config.new(
        ttl: ttl, delay: method(:renewal_delay),
        shutdown_timeout: RENEWER_SHUTDOWN_TIMEOUT_SECONDS
      )
      LockRenewer.new(self, key, guard, config)
    end

    def renewal_delay(ttl, remaining: nil)
      delay = [ttl / 3.0, MAX_RENEWAL_DELAY_SECONDS].min
      latest = latest_renewal_delay(remaining)
      delay = [delay, latest].min if latest
      jittered = [0.0, delay * (0.9 + (rand * 0.2))].max
      latest ? [jittered, latest].min : jittered
    end

    def latest_renewal_delay(remaining)
      return unless remaining

      [0.0, remaining - RENEWAL_SAFETY_MARGIN_SECONDS - RENEWAL_REQUEST_BUDGET_SECONDS].max
    end

    def validate_ttl(ttl)
      valid = ttl.is_a?(Integer) && ttl.between?(MIN_LOCK_TTL_SECONDS, MAX_LOCK_TTL_SECONDS)
      raise ArgumentError, 'ttl must be an integer between 5 seconds and 90 days' unless valid
    end
  end
end
