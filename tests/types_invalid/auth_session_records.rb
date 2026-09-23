# frozen_string_literal: true

Volcano::AuthSession.new(
  id: 'session', user_id: 'user', provider: 'email', expires_at: 'tomorrow',
  is_active: true, is_current: false
)
Volcano::AuthSession.new(id: 'session', user_id: 'user')
Volcano::AuthSession['session', 'user', 'email', Time.now, true, false]
  .with(is_active: 'yes')

Volcano::SessionPage.new(sessions: ['not a session'], total: 1, page: 1, limit: 20, total_pages: 1)
Volcano::SessionPage[[Volcano::AuthSession['session', 'user', 'email', Time.now, true, false]], 'one', 1, 20, 1]
