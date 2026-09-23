# frozen_string_literal: true

require 'volcano'

client = Volcano::Client.new(anon_key: 'anon-key')
Volcano::Client.new(anon_key: 'anon-key', timeout: 1.5)
client.current_session
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

# @type method typed_timestamp_calls: (Volcano::Client) -> void
def typed_timestamp_calls(client)
  client.logs.search('project', resource: { id: 'worker' }, start_time: Time.utc(2026), end_time: Time.utc(2026, 2))
end

# @type method typed_lock_result: (Volcano::Client) -> String
def typed_lock_result(client)
  client.locks.with_lock('job', ttl: 30) { |guard| guard.lease.key }
end

# @type method typed_function_keywords: (Volcano::Client) -> Volcano::FunctionResponse
def typed_function_keywords(client)
  client.functions.invoke('hello', name: 'Ada')
end
