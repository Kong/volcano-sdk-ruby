# frozen_string_literal: true

require 'volcano'

result = Volcano::ConfirmEmailResult.new('Email confirmed successfully', 'https://app.example.com/welcome')
raise 'Wrong members' unless Volcano::ConfirmEmailResult.members == %i[message redirect_to]
raise 'Wrong instance members' unless result.members == Volcano::ConfirmEmailResult.members
raise 'Wrong message' unless result.message == 'Email confirmed successfully'
raise 'Wrong redirect' unless result.redirect_to == 'https://app.example.com/welcome'

empty_result = Volcano::ConfirmEmailResult[message: nil, redirect_to: nil]
updated_result = empty_result.with(message: 'Done', redirect_to: 'https://app.example.com/next')
raise 'Wrong update' unless updated_result.to_h == { message: 'Done', redirect_to: 'https://app.example.com/next' }

transformed = updated_result.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed result' unless transformed['message'] == 'Done'
raise 'Wrong deconstruction' unless updated_result.deconstruct == ['Done', 'https://app.example.com/next']
raise 'Wrong selected key' unless updated_result.deconstruct_keys([:message])[:message] == 'Done'
raise 'Wrong full keys' unless updated_result.deconstruct_keys(nil)[:redirect_to] == 'https://app.example.com/next'
