# frozen_string_literal: true

Volcano::EmailChangeResult.new(message: 'Confirmation sent')
Volcano::EmailChangeResult[message: 7, new_email: nil]
Volcano::EmailChangeResult.new(message: nil, new_email: nil).with(new_email: 7)
Volcano::EmailChangeResult.new(message: nil, new_email: nil).deconstruct_keys
