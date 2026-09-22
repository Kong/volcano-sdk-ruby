# frozen_string_literal: true

Volcano::Session.new(access_token: 7)
Volcano::Session[access_token: 7]
Volcano::Session.new(access_token: 'valid').with(access_token: 7)
Volcano::Session.new(access_token: 'valid').deconstruct_keys
