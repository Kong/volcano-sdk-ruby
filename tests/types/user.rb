# frozen_string_literal: true

require 'volcano'

user = Volcano::User.new(id: 'user', email: 'user@example.com', status: 'active')
raise 'Wrong user' unless user.id == 'user' && user.project_id.nil?
raise 'Wrong members' unless Volcano::User.members == %i[
  id project_id email email_confirmed user_metadata app_metadata avatar_url status
  banned_until last_sign_in_at created_at updated_at
]

positional = Volcano::User.new('user', nil, 'user@example.com', nil, nil, nil, nil, 'active')
raise 'Wrong positional constructor' unless positional == user
raise 'Wrong positional bracket constructor' unless Volcano::User[
  'user', nil, 'user@example.com', nil, nil, nil, nil, 'active'
] == user

timestamp = Time.utc(2026, 9, 22)
updated = user.with(user_metadata: { 'roles' => ['admin'] }, last_sign_in_at: timestamp)
raise 'Wrong metadata' unless updated.user_metadata == { 'roles' => ['admin'] }
raise 'Wrong snapshot' unless updated.to_h[:last_sign_in_at] == timestamp
raise 'Wrong tuple' unless updated.deconstruct[7] == 'active'
raise 'Wrong keys' unless updated.deconstruct_keys([:email])[:email] == 'user@example.com'

mapped = updated.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped user' unless mapped['status'] == 'active'
