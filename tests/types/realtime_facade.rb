# frozen_string_literal: true

require 'volcano'

client = Volcano::Client.new(anon_key: 'anon-key')
realtime = client.realtime
realtime.database_name = 'app'
channel = realtime.channel('room')
string_type_channel = realtime.channel('presence-room', type: 'presence')
channel.on('message') { |event| event.fetch('value', nil) }
string_type_channel.on('join') { |event| raise if event.client.empty? }
string_type_channel.on('presence_sync') { |state| state.each_value(&:client) }
channel.on('message', ->(_event) {})
unsubscribe = realtime.on_connect { |_context| nil }

raise 'Wrong realtime database name' unless realtime.database_name == 'app'
raise 'Wrong channel name' unless channel.name == 'broadcast:room'
raise 'Wrong string channel type' unless string_type_channel.name == 'presence:presence-room'
raise 'Connection must start disconnected' if realtime.connected?
raise 'Wrong presence state' unless channel.presence_state.empty?
raise 'Wrong tracked state' unless channel.tracked_state.empty?

unsubscribe.call
realtime.remove_channel('room')
realtime.remove_channel('presence-room', type: 'presence')
realtime.disconnect

# @type method typed_realtime_callbacks: (Volcano::Realtime::Channel) -> void
def typed_realtime_callbacks(channel)
  channel.on_presence_sync { |state| state.each_value { |entry| raise if entry.client.empty? } }
  channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') { |change| change.type == 'INSERT' }
  channel.on('INSERT') { |change| raise if change.table.empty? }
  channel.track('online' => true)
  channel.send(event: 'message', text: 'hello')
end

# @type method typed_authenticated_realtime: (Volcano::Client) -> void
def typed_authenticated_realtime(client)
  client.auth.sign_in(email: 'user@example.test', password: 'password')
  client.realtime.channel('room').subscribe
end
