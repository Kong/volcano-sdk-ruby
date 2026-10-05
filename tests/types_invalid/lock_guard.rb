# frozen_string_literal: true

# @type method invalid_lock_timeout: (Volcano::LockGuard) -> bool
def invalid_lock_timeout(guard)
  guard.wait_lost(timeout: 'later')
end

Volcano::LockGuard.new
