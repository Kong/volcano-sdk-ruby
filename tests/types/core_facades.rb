# frozen_string_literal: true

require 'volcano'

client = Volcano::Client.new(anon_key: 'anon-key')
client.database('app')
client.functions
client.durable
client.logs
client.locks

# @type method typed_core_calls: (Volcano::Client) -> void
def typed_core_calls(client)
  client.database('app').from('records').select('id').eq('owner', 'user').limit(1).execute
  client.functions.invoke('worker', 'id' => 1)
  client.durable.list('project', 'worker', page: 1)
  client.logs.search('project', 'limit' => 1)
  client.locks.acquire('job', ttl: 30)
end
