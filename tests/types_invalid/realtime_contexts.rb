# frozen_string_literal: true

Volcano::Realtime::ConnectContext.new(client: 123)
Volcano::Realtime::DisconnectContext.new(code: 'bad', reason: 'manual')
Volcano::Realtime::ErrorContext.new(code: nil, message: 'offline', error: 'not an exception')
Volcano::Realtime::PresenceInfo.new(client: 'client', data: ['not a map'])
Volcano::Realtime::PresenceInfo.new(client: 'client').with(user: 123)
