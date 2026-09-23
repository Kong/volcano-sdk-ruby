# frozen_string_literal: true

require 'volcano'

connect = Volcano::Realtime::ConnectContext.new(client: 'client-123')
raise 'Wrong connected client' unless connect.client == 'client-123'
raise 'Wrong positional connection' unless Volcano::Realtime::ConnectContext.new('client-123') == connect
raise 'Wrong bracket connection' unless Volcano::Realtime::ConnectContext[client: 'client-123'] == connect
raise 'Wrong connection members' unless Volcano::Realtime::ConnectContext.members == [:client]
raise 'Wrong connection update' unless connect.with(client: nil).client.nil?
raise 'Wrong connection snapshot' unless connect.to_h[:client] == 'client-123'
raise 'Wrong connection tuple' unless connect.deconstruct == ['client-123']
raise 'Wrong connection keys' unless connect.deconstruct_keys([:client])[:client] == 'client-123'

disconnect = Volcano::Realtime::DisconnectContext.new(code: nil, reason: 'manual')
raise 'Wrong disconnect reason' unless disconnect.reason == 'manual'
raise 'Wrong positional disconnect' unless Volcano::Realtime::DisconnectContext.new(nil, 'manual') == disconnect
raise 'Wrong disconnect update' unless disconnect.with(code: 1000).code == 1000
raise 'Wrong disconnect snapshot' unless disconnect.to_h[:reason] == 'manual'
raise 'Wrong disconnect tuple' unless disconnect.deconstruct == [nil, 'manual']
raise 'Wrong disconnect keys' unless disconnect.deconstruct_keys([:reason])[:reason] == 'manual'

error = StandardError.new('offline')
failure = Volcano::Realtime::ErrorContext.new(code: 'offline', message: 'offline', error: error)
raise 'Wrong error context' unless failure.error.equal?(error)
raise 'Wrong positional error' unless Volcano::Realtime::ErrorContext.new('offline', 'offline', error) == failure
raise 'Wrong error update' unless failure.with(code: 1006).code == 1006
raise 'Wrong error snapshot' unless failure.to_h[:message] == 'offline'
raise 'Wrong error tuple' unless failure.deconstruct == ['offline', 'offline', error]
raise 'Wrong error keys' unless failure.deconstruct_keys([:error])[:error].equal?(error)

presence = Volcano::Realtime::PresenceInfo.new(client: 'client-123', data: { 'online' => true })
raise 'Wrong presence client' unless presence.client == 'client-123' && presence.user.nil?

positional_presence = Volcano::Realtime::PresenceInfo.new('client-123', nil, { 'online' => true })
raise 'Wrong positional presence' unless positional_presence == presence
raise 'Wrong bracket presence' unless Volcano::Realtime::PresenceInfo['client-123'] == presence.with(data: {})
raise 'Wrong presence update' unless presence.with(user: 'user-123').user == 'user-123'
raise 'Wrong presence snapshot' unless presence.to_h[:data] == { 'online' => true }
raise 'Wrong presence tuple' unless presence.deconstruct == ['client-123', nil, { 'online' => true }]
raise 'Wrong presence keys' unless presence.deconstruct_keys([:client])[:client] == 'client-123'

mapped = presence.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped presence' unless mapped['client'] == 'client-123'
