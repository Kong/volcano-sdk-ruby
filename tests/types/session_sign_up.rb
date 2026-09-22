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
