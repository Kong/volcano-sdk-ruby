# frozen_string_literal: true

def contract
  raise 'contract world is not initialized' unless @contract

  @contract
end

Given('the confirmed contract user') do
  raise 'fixture user is missing' if contract.fixture.fetch('user_id').to_s.empty?
end

When("the client signs in with the contract user's credentials") do
  contract.record { contract.authenticate }
end

Then('the SDK operation succeeds') do
  outcome = contract.last_outcome
  raise 'SDK operation did not run' unless outcome
  raise "SDK operation failed (#{outcome.category}): #{outcome.error}" unless outcome.ok
end

Then('the current session belongs to the contract user') do
  expected_user_id = contract.fixture.fetch('user_id')
  raise 'sign-in returned the wrong user' unless contract.last_outcome.value.user_id == expected_user_id
  raise 'current session has the wrong user' unless contract.client.current_session.user_id == expected_user_id
end

Given('an authenticated client') do
  contract.authenticate
end

When('the client selects the contract table where "slug" equals the fixture slug') do
  contract.record do
    contract.client
            .database(contract.fixture.fetch('database_name'))
            .from(contract.fixture.fetch('table_name'))
            .select('*')
            .eq('slug', contract.fixture.fetch('fixture_row').fetch('slug'))
            .execute
  end
end

Then('exactly the fixture row is returned') do
  expected_rows = [contract.fixture.fetch('fixture_row')]
  raise 'database result did not match the fixture row' unless contract.last_outcome.value == expected_rows
end

When('the client uploads and downloads the contract object') do
  contract.record do
    bucket = contract.client.storage.from(contract.fixture.fetch('bucket_name'))
    bucket.upload(contract.storage_path, contract.storage_bytes)
    bucket.download(contract.storage_path)
  end
end

Then('the downloaded bytes equal the uploaded bytes') do
  raise 'downloaded bytes changed' unless contract.last_outcome.value == contract.storage_bytes
end

Given('a service-role client') do
  raise 'fixture service key is missing' if contract.fixture.fetch('service_key').to_s.empty?
end

When('the client acquires and releases the contract lock') do
  contract.record do
    lease = contract.service_client.locks.acquire(contract.lock_key, ttl: 10)
    cleanup = contract.register_lock_cleanup(contract.lock_key, lease)
    contract.service_client.locks.release(contract.lock_key, lease)
    contract.remove_cleanup(cleanup)

    replacement = contract.service_client.locks.acquire(contract.lock_key, ttl: 10)
    replacement_cleanup = contract.register_lock_cleanup(contract.lock_key, replacement)
    contract.service_client.locks.release(contract.lock_key, replacement)
    contract.remove_cleanup(replacement_cleanup)
    { 'lease' => lease, 'released' => replacement.token != lease.token }
  end
end

Then('the released lease is no longer held') do
  raise 'released lock could not be acquired again' unless contract.last_outcome.value.fetch('released')
end

Given('two authenticated realtime clients') do
  contract.record do
    clients = [
      contract.client,
      Volcano::Client.new(
        api_url: contract.fixture.fetch('api_url'),
        anon_key: contract.fixture.fetch('anon_key')
      )
    ]
    clients.each { |client| contract.authenticate(client) }
    contract.realtime_clients.concat(clients)
    contract.subscriber = clients.fetch(0).realtime.channel(contract.realtime_channel)
    contract.publisher = clients.fetch(1).realtime.channel(contract.realtime_channel)
    clients
  end
end

When('one client subscribes and the other publishes the contract message') do
  return if contract.last_outcome && !contract.last_outcome.ok

  contract.record do
    Async do |task|
      received = Async::Queue.new
      contract.subscriber.on('message') { |message| received.enqueue(message) }
      contract.subscriber.subscribe
      contract.publisher.subscribe
      contract.publisher.send(**contract.realtime_message.transform_keys(&:to_sym))
      task.with_timeout(10) { received.dequeue }
    ensure
      contract.realtime_clients.reverse_each { |client| client.realtime.disconnect }
    end.wait
  end
end

Then('the subscriber receives the contract message within 10 seconds') do
  raise 'realtime message did not match' unless contract.last_outcome.value == contract.realtime_message
end
