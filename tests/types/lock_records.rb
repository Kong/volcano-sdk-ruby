# frozen_string_literal: true

require 'volcano'

expiry = Time.utc(2026, 8, 26)
lease = Volcano::LockLease.new('build', 'owner', expiry, 7)
raise 'Wrong lease members' unless Volcano::LockLease.members == %i[key token expires_at fencing_token]
raise 'Wrong lease instance members' unless lease.members == Volcano::LockLease.members
raise 'Wrong lease token' unless lease.token == 'owner'
raise 'Wrong lease expiry' unless lease.expires_at == expiry

bracket_lease = Volcano::LockLease[key: 'build', token: 'other', expires_at: nil, fencing_token: 8]
updated_lease = bracket_lease.with(token: 'owner', expires_at: expiry)
raise 'Wrong lease update' unless updated_lease.to_h[:token] == 'owner'

transformed_lease = updated_lease.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed lease' unless transformed_lease['token'] == 'owner'
raise 'Wrong lease tuple' unless updated_lease.deconstruct == ['build', 'owner', expiry, 8]
raise 'Wrong lease keys' unless updated_lease.deconstruct_keys([:token])[:token] == 'owner'
raise 'Wrong full lease' unless updated_lease.deconstruct_keys(nil)[:fencing_token] == 8

state = Volcano::LockState.new(false, nil, nil)
raise 'Wrong state members' unless Volcano::LockState.members == %i[held expires_at fencing_token]
raise 'Wrong state instance members' unless state.members == Volcano::LockState.members
raise 'Wrong unheld state' unless state.held == false && state.expires_at.nil?

bracket_state = Volcano::LockState[held: true, expires_at: expiry, fencing_token: 7]
updated_state = bracket_state.with(fencing_token: 8)
raise 'Wrong state update' unless updated_state.to_h[:fencing_token] == 8

transformed_state = updated_state.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong transformed state' unless transformed_state['held'] == 'true'
raise 'Wrong state tuple' unless updated_state.deconstruct == [true, expiry, 8]
raise 'Wrong state keys' unless updated_state.deconstruct_keys([:held])[:held] == true
raise 'Wrong full state' unless updated_state.deconstruct_keys(nil)[:fencing_token] == 8
