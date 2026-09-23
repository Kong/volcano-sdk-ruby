# frozen_string_literal: true

require 'volcano'

# @type method inspect_lock_guard: (Volcano::LockGuard) -> String
def inspect_lock_guard(guard)
  guard.lease.key + (guard.lost? ? ' lost' : ' held')
end
