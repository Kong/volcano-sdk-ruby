# frozen_string_literal: true

INVALID_AUTH_REFRESH = 'invalid-contract-refresh-token'

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
  raise "SDK operation failed (#{outcome.category})" unless outcome.ok
end

Then('the SDK operation fails') do
  outcome = contract.last_outcome
  raise 'SDK operation did not run' unless outcome
  raise 'SDK operation unexpectedly succeeded' if outcome.ok
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

Given('a unique unconfirmed contract user') do
  raise 'unique user is missing' unless contract.unique_email.end_with?('@example.com')
end

When("the client signs up with the new user's credentials") do
  contract.record do
    contract.client.auth.sign_up(
      email: contract.unique_email,
      password: contract.unique_password
    )
  end
end

Then('sign-up is acknowledged without a session') do
  raise 'sign-up did not run' unless contract.last_outcome
  raise 'sign-up unexpectedly returned a session' if contract.last_outcome.value.session
end

Then('the current session is empty') do
  raise 'current session was not cleared' if contract.client.current_session
end

Given('the client is signed in as the confirmed contract user') do
  contract.authenticate
end

When('the client retrieves the current user') do
  contract.record { contract.client.auth.get_user }
end

Then('the current user belongs to the contract user') do
  user = contract.client.current_user
  raise 'current user has the wrong identity' unless user&.id == contract.fixture.fetch('user_id')
end

When("the client updates the current user's metadata") do
  contract.record do
    contract.client.auth.update_user(
      user_metadata: { 'contract_marker' => contract.metadata_marker }
    )
  end
end

Then('the current user contains the updated metadata') do
  metadata = contract.client.current_user&.user_metadata
  raise 'current user metadata was not updated' unless metadata&.fetch('contract_marker') == contract.metadata_marker
end

When('the client refreshes the current session') do
  session = contract.client.current_session
  raise 'current session is missing' unless session

  contract.previous_access_token = session.access_token
  contract.previous_refresh_token = session.refresh_token
  contract.record { contract.client.auth.refresh_session }
end

Then('the current session exposes rotated access and refresh tokens') do
  session = contract.client.current_session
  raise 'current session is missing' unless session
  raise 'access token did not rotate' if session.access_token == contract.previous_access_token
  raise 'refresh token is missing' if session.refresh_token.to_s.empty?
  raise 'refresh token did not rotate' if session.refresh_token == contract.previous_refresh_token
end

When('the client refreshes with an invalid refresh token') do
  session = contract.client.current_session
  raise 'current session is missing' unless session

  contract.client = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key'),
    access_token: session.access_token,
    refresh_token: INVALID_AUTH_REFRESH
  )
  contract.record { contract.client.auth.refresh_session }
end

When('the client signs out') do
  contract.record { contract.client.auth.sign_out }
end

When('the client subscribes to auth-state changes') do
  contract.unsubscribe_auth = contract.client.auth.on_auth_state_change do |user|
    contract.listener_events << user&.id
  end
end

Then('the listener immediately observes the current user') do
  expected = [contract.fixture.fetch('user_id')]
  raise 'listener did not observe the current user' unless contract.listener_events == expected
end

Then('the listener observes the signed-out state') do
  raise 'listener did not observe sign-out' unless contract.listener_events.last.nil?
end

When('the client unsubscribes from auth-state changes') do
  raise 'listener unsubscribe is missing' unless contract.unsubscribe_auth

  contract.unsubscribe_auth.call
  contract.listener_event_count = contract.listener_events.length
end

Then('the listener receives no additional events') do
  unless contract.listener_events.length == contract.listener_event_count
    raise 'listener received an event after unsubscribe'
  end
end

Given('a unique anonymous contract user') do
  raise 'unique user is missing' unless contract.unique_email.end_with?('@example.com')
end

When('the client signs up anonymously') do
  outcome = contract.record { contract.client.auth.sign_up_anonymous }
  contract.anonymous_user_id = outcome.value.user_id if outcome.ok
end

Then('the current session belongs to the anonymous user') do
  user_id = contract.client.current_session&.user_id
  raise 'anonymous session has the wrong identity' unless user_id == contract.anonymous_user_id
end

When('the client converts the anonymous user with credentials') do
  contract.record do
    contract.client.auth.convert_anonymous(
      email: contract.unique_email,
      password: contract.unique_password
    )
  end
end

Then('the converted user keeps the anonymous user identity') do
  user_id = contract.client.current_user&.id
  raise 'anonymous identity changed during conversion' unless user_id == contract.anonymous_user_id
end

Given('the client is signed in as the confirmed contract user on multiple sessions') do
  contract.authenticate
  contract.secondary_client = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key')
  )
  contract.authenticate(contract.secondary_client)
end

When("the client lists the current user's sessions") do
  contract.record { contract.client.auth.get_sessions }
end

Then('the session list contains the current session') do
  sessions = contract.last_outcome&.value&.sessions
  raise 'session list does not contain the current session' unless sessions&.any?(&:is_current)
end

When('the client deletes another current-user session') do
  other = contract.client.auth.get_sessions.sessions.find { |session| !session.is_current }
  raise 'another session is missing' unless other

  contract.deleted_session_id = other.id
  contract.record do
    contract.client.auth.delete_session(session_id: other.id)
    contract.client.auth.get_sessions
  end
end

Then('the deleted session is absent from the session list') do
  sessions = contract.last_outcome&.value&.sessions
  raise 'deleted session remains present' if sessions&.any? { |session| session.id == contract.deleted_session_id }
end

When('the client deletes all current-user sessions') do
  contract.record do
    contract.authenticate(contract.secondary_client)
    contract.client.auth.delete_all_other_sessions
    begin
      contract.secondary_client.auth.get_user
      raise 'deleted secondary session remains authenticated'
    rescue Volcano::Error::AuthenticationError
      nil
    end
    contract.client.auth.sign_out
  end
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
