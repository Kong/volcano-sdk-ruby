# frozen_string_literal: true

Volcano::User.new(id: 'user', email: 'user@example.com', status: 'active', email_confirmed: 'yes')
Volcano::User.new(id: 'user', email: 'user@example.com')
Volcano::User['user', nil, 'user@example.com', nil, nil, nil, nil, 'active']
  .with(last_sign_in_at: 'yesterday')
