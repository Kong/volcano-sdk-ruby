# frozen_string_literal: true

require 'volcano'

session = Volcano::Session.new('access', 'refresh', 'user', { id: 'user', role: :admin })
raise 'Wrong members' unless Volcano::Session.members == %i[access_token refresh_token user_id user]
raise 'Wrong instance members' unless session.members == Volcano::Session.members
raise 'Wrong user' unless session.user == { 'id' => 'user', 'role' => 'admin' }

bracket_session = Volcano::Session[access_token: 'bracket', user: { 'id' => 'user' }]
updated_session = bracket_session.with(access_token: 'updated', user: { id: 'user', role: :reader })
raise 'Wrong updated token' unless updated_session.access_token == 'updated'
raise 'Wrong snapshot' unless updated_session.to_h[:user] == updated_session.user

transformed_session = updated_session.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed snapshot' unless transformed_session['access_token'] == 'updated'
raise 'Wrong deconstruction' unless updated_session.deconstruct[0] == 'updated'
raise 'Wrong key deconstruction' unless updated_session.deconstruct_keys([:access_token])[:access_token] == 'updated'
raise 'Wrong full deconstruction' unless updated_session.deconstruct_keys(nil)[:access_token] == 'updated'

result = Volcano::SignUpResult.new(false, 'Accepted', updated_session)
raise 'Wrong result members' unless Volcano::SignUpResult.members == %i[confirmation_required message session]
raise 'Wrong instance result members' unless result.members == Volcano::SignUpResult.members
raise 'Wrong session' unless result.session&.access_token == 'updated'

bracket_result = Volcano::SignUpResult[confirmation_required: true, message: 'Confirm']
updated_result = bracket_result.with(confirmation_required: false, message: 'Done', session: result.session)
raise 'Wrong result update' unless updated_result.to_h[:message] == 'Done'

transformed_result = updated_result.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed result' unless transformed_result['message'] == 'Done'
raise 'Wrong result deconstruction' unless updated_result.deconstruct[0] == false
raise 'Wrong result keys' unless updated_result.deconstruct_keys([:message])[:message] == 'Done'
raise 'Wrong full result keys' unless updated_result.deconstruct_keys(nil)[:message] == 'Done'
