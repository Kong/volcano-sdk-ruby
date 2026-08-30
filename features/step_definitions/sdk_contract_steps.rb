# frozen_string_literal: true

ACCESS_TOKEN_CLOCK_TICK_SECONDS = 1.1

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

When('the client reads the current session') do
  contract.record { contract.client.auth.current_session }
end

When('a fresh client adopts the current session') do
  contract.record do
    source = contract.client.auth.current_session
    raise 'current session is missing' unless source

    target = Volcano::Client.new(
      api_url: contract.fixture.fetch('api_url'),
      anon_key: contract.fixture.fetch('anon_key')
    )
    target.auth.current_session = source
    contract.client = target
    target.auth.current_session
  end
end

When('the client refreshes the current session') do
  contract.previous_session = contract.client.auth.current_session
  raise 'current session is missing' unless contract.previous_session

  sleep ACCESS_TOKEN_CLOCK_TICK_SECONDS
  contract.record { contract.client.auth.refresh_session }
end

When('the client signs out') do
  contract.signed_out_session = contract.client.auth.current_session
  raise 'current session is missing' unless contract.signed_out_session

  contract.record { contract.client.auth.sign_out }
end

When('a fresh client tries to refresh the signed-out session') do
  target = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key')
  )
  target.auth.current_session = contract.signed_out_session
  contract.client = target
  contract.record { target.auth.refresh_session }
end

Then('the refreshed session becomes current') do
  refreshed = contract.last_outcome.value
  raise 'refresh returned the previous session' if refreshed.equal?(contract.previous_session)
  raise 'refresh did not issue a new access token' if refreshed.access_token == contract.previous_session.access_token
  raise 'refreshed session is not current' unless contract.client.auth.current_session.equal?(refreshed)
end

Then('the SDK operation succeeds') do
  outcome = contract.last_outcome
  raise 'SDK operation did not run' unless outcome
  raise "SDK operation failed (#{outcome.category}): #{outcome.error}" unless outcome.ok
end

Then('the SDK operation fails with an authentication error') do
  outcome = contract.last_outcome
  raise 'SDK operation unexpectedly succeeded' if outcome&.ok
  raise "expected authentication error, got #{outcome&.category}" unless outcome&.category == 'authentication error'
end

Then('the current session is empty') do
  raise 'current session is not empty' if contract.client.auth.current_session
end

Then('the current session belongs to the contract user') do
  expected_user_id = contract.fixture.fetch('user_id')
  raise 'sign-in returned the wrong user' unless contract.last_outcome.value.user_id == expected_user_id
  raise 'current session has the wrong user' unless contract.client.current_session.user_id == expected_user_id
end

Then('the current session exposes access and refresh tokens') do
  session = contract.client.current_session
  raise 'current session is missing an access token' if session.access_token.to_s.empty?
  raise 'current session is missing a refresh token' if session.refresh_token.to_s.empty?
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
    uploaded = bucket.upload(contract.storage_path, contract.storage_bytes)
    { 'bytes' => bucket.download(contract.storage_path), 'path' => uploaded.fetch('name') }
  end
end

Then('the downloaded bytes equal the uploaded bytes') do
  raise 'downloaded bytes changed' unless contract.last_outcome.value.fetch('bytes') == contract.storage_bytes
end

Then('the stored object path equals the contract path') do
  raise 'stored object path changed' unless contract.last_outcome.value.fetch('path') == contract.storage_path
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
  raise contract.last_outcome.error if contract.last_outcome && !contract.last_outcome.ok

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
