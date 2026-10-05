# frozen_string_literal: true

client = Volcano::Client.new(anon_key: 42)
realtime = client.realtime
realtime.database_name = 12
channel = realtime.channel('room', type: 8)
channel.on(42) { nil }
channel.track([])
