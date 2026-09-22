# frozen_string_literal: true

Volcano::SignUpResult.new(confirmation_required: 'yes', message: 'Accepted')
Volcano::SignUpResult[confirmation_required: 'yes', message: 'Accepted']
Volcano::SignUpResult.new(confirmation_required: false, message: 'Accepted').with(message: 7)
Volcano::SignUpResult.new(confirmation_required: false, message: 'Accepted').deconstruct_keys
