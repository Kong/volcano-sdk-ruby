# frozen_string_literal: true

require 'volcano'

# @type method inspect_lock_guard: (Volcano::LockGuard) -> String
def inspect_lock_guard(guard)
  guard.lease.key + (guard.lost? ? ' lost' : ' held')
end

# @type method build_lock_guard: (Volcano::LockLease, Volcano::_LeaseStartedAt) -> Volcano::LockGuard
def build_lock_guard(lease, started_at)
  Volcano::LockGuard.new(lease, ttl: 5, started_at: started_at)
end
