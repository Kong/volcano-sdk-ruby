# frozen_string_literal: true

# @type method invalid_complex_timeout: (Volcano::LockGuard) -> bool
def invalid_complex_timeout(guard)
  guard.wait_lost(timeout: Complex(1, 1))
end
