# frozen_string_literal: true

require 'volcano'

# @type method session_page: (Volcano::Auth) -> Volcano::SessionPage
def session_page(auth)
  auth.list_sessions(page: 2, limit: 10)
end

# @type method delete_other_sessions: (Volcano::Auth) -> nil
def delete_other_sessions(auth)
  auth.delete_all_other_sessions
end

# @type method delete_one_session: (Volcano::Auth) -> nil
def delete_one_session(auth)
  auth.delete_session('00000000-0000-4000-8000-000000000099')
end
