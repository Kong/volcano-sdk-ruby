# frozen_string_literal: true

require 'volcano'

expiry = Time.utc(2026, 9, 30)
session = Volcano::AuthSession.new(
  id: 'session', user_id: 'user', provider: 'email', expires_at: expiry,
  is_active: true, is_current: false
)
raise 'Wrong session' unless session.id == 'session' && session.user_agent.nil?
raise 'Wrong session members' unless Volcano::AuthSession.members == %i[
  id user_id provider expires_at is_active is_current user_agent ip_address last_ip_address
  last_activity_at session_started_at created_at updated_at
]

positional = Volcano::AuthSession['session', 'user', 'email', expiry, true, false]
raise 'Wrong positional session' unless positional == session

positional_new = Volcano::AuthSession.new('session', 'user', 'email', expiry, true, false)
raise 'Wrong positional constructor' unless positional_new == session

updated = session.with(user_agent: 'Volcano Test', last_activity_at: expiry)
raise 'Wrong session update' unless updated.user_agent == 'Volcano Test'
raise 'Wrong session snapshot' unless updated.to_h[:last_activity_at] == expiry
raise 'Wrong session tuple' unless updated.deconstruct[6] == 'Volcano Test'
raise 'Wrong session keys' unless updated.deconstruct_keys([:user_agent])[:user_agent] == 'Volcano Test'

mapped = updated.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped session' unless mapped['provider'] == 'email'

page = Volcano::SessionPage.new(sessions: [session], total: 1, page: 1, limit: 20, total_pages: 1)
raise 'Wrong page' unless page.sessions == [session] && page.total == 1
raise 'Wrong page members' unless Volcano::SessionPage.members == %i[
  sessions total page limit total_pages
]

positional_page = Volcano::SessionPage[[session], 1, 1, 20, 1]
raise 'Wrong positional page' unless positional_page == page
raise 'Wrong positional page constructor' unless Volcano::SessionPage.new([session], 1, 1, 20, 1) == page

updated_page = page.with(page: 2)
raise 'Wrong page update' unless updated_page.page == 2
raise 'Wrong page snapshot' unless updated_page.to_h[:sessions] == [session]
raise 'Wrong page tuple' unless updated_page.deconstruct == [[session], 1, 2, 20, 1]
raise 'Wrong page keys' unless updated_page.deconstruct_keys([:page])[:page] == 2

mapped_page = updated_page.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped page' unless mapped_page['page'] == '2'
