# frozen_string_literal: true

client = Volcano::Client.new(anon_key: 'anon-key')
client.database(4)
client.database('app').from(12)
client.functions.invoke(17)
client.durable.list(12, 'worker')
client.durable.approvals.list('project', page: '2')
client.durable.approvals.approve('project', 'approval', comment: 42)
client.logs.search(12, {})
client.locks.acquire('job', ttl: 'thirty')
