# frozen_string_literal: true

client = Volcano::Client.new(anon_key: 'anon-key')
client.database(4)
client.database('app').from(12)
client.functions.invoke(17)
client.durable.list(12, 'worker')
client.logs.search(12, {})
client.locks.acquire('job', ttl: 'thirty')
