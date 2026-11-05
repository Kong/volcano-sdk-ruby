# frozen_string_literal: true

Volcano::ConfirmEmailResult.new(message: 'Email confirmed successfully')
Volcano::ConfirmEmailResult[message: 7, redirect_to: nil]
Volcano::ConfirmEmailResult.new(message: nil, redirect_to: nil).with(redirect_to: 7)
Volcano::ConfirmEmailResult.new(message: nil, redirect_to: nil).deconstruct_keys
