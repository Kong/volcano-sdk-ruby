# frozen_string_literal: true

require 'volcano'

error = Volcano::Error::RateLimitedError.new('limited', status: 429, code: 'rate_limited', retry_after: 17)
raise 'Wrong error status' unless error.status == 429
raise 'Wrong error code' unless error.code == 'rate_limited'
raise 'Wrong retry delay' unless error.retry_after == 17

changed = Volcano::Error::SessionChangedError.new
raise 'Wrong default status' unless changed.status == 409
raise 'Wrong default code' unless changed.code == 'auth_session_changed'
raise 'Wrong default delay' unless changed.retry_after.nil?
