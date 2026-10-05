# frozen_string_literal: true

Volcano::LockLease.new(key: 'build', token: 'owner', expires_at: nil)
Volcano::LockLease[key: 'build', token: 7, expires_at: nil, fencing_token: 1]
Volcano::LockLease.new(key: 'build', token: 'owner', expires_at: nil, fencing_token: 1).with(key: 7)
Volcano::LockLease.new(key: 'build', token: 'owner', expires_at: nil, fencing_token: 1).deconstruct_keys
Volcano::LockState.new(held: 'yes', expires_at: nil, fencing_token: nil)
Volcano::LockState[held: false, expires_at: nil, fencing_token: 'wrong']
