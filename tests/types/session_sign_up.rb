# frozen_string_literal: true

require 'volcano'

session = Volcano::Session.new('access', 'refresh', 'user', { 'id' => 'user' })
result = Volcano::SignUpResult.new(
  confirmation_required: false,
  message: 'Signed up',
  session: session
)
raise 'Wrong session' unless result.session&.access_token == 'access'
raise 'Wrong message' unless Volcano::SignUpResult.new(false, 'Accepted').message == 'Accepted'

symbol_session = Volcano::Session[access_token: 'access', user: { id: 'user', profile: { role: :reader } }]
updated_session = symbol_session.with(access_token: 'next', user: { id: 'user' })
updated_result = Volcano::SignUpResult[false, 'Accepted', updated_session].with(message: 'Updated')
raise 'Wrong update' unless updated_result.session&.access_token == 'next'
