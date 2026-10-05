# frozen_string_literal: true

require 'volcano'

result = Volcano::EmailChangeResult.new('Confirmation sent', 'new@example.com')
raise 'Wrong members' unless Volcano::EmailChangeResult.members == %i[message new_email]
raise 'Wrong instance members' unless result.members == Volcano::EmailChangeResult.members
raise 'Wrong message' unless result.message == 'Confirmation sent'
raise 'Wrong email' unless result.new_email == 'new@example.com'

empty_result = Volcano::EmailChangeResult[message: nil, new_email: nil]
updated_result = empty_result.with(message: 'Done', new_email: 'new@example.com')
raise 'Wrong update' unless updated_result.to_h == { message: 'Done', new_email: 'new@example.com' }

transformed = updated_result.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed result' unless transformed['message'] == 'Done'
raise 'Wrong deconstruction' unless updated_result.deconstruct == ['Done', 'new@example.com']
raise 'Wrong selected key' unless updated_result.deconstruct_keys([:message])[:message] == 'Done'
raise 'Wrong full keys' unless updated_result.deconstruct_keys(nil)[:new_email] == 'new@example.com'
