# frozen_string_literal: true

# @type method invalid_session_calls: (Volcano::Auth) -> void
def invalid_session_calls(auth)
  auth.list_sessions(page: 'two')
  auth.delete_session(99)
  auth.delete_all_other_sessions('unexpected')
end
