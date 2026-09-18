# frozen_string_literal: true

require 'net/http'

ACCESS_TOKEN_CLOCK_TICK_SECONDS = 1.1

def contract
  raise 'contract world is not initialized' unless @contract

  @contract
end

Given('the confirmed contract user') do
  raise 'fixture user is missing' if contract.fixture.fetch('user_id').to_s.empty?
end

Given('the client listens for auth state changes') do
  subscription = contract.client.auth.on_auth_state_change do |_event, session|
    contract.auth_state_sessions << session
  end
  contract.register_cleanup(-> { subscription.unsubscribe })
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

When('a fresh client tries to refresh a supplied profile without a session identifier') do
  source = contract.client.current_session
  raise 'current session is missing' unless source

  target = Volcano::Client.new(api_url: contract.fixture.fetch('api_url'), anon_key: contract.fixture.fetch('anon_key'))
  supplied = source.with(access_token: 'sdk-contract-rejected-access-token')
  target.auth.current_session = supplied
  contract.record { target.auth.refresh_session }
  raise 'supplied credentials changed' unless target.current_session == supplied
end

When('a fresh client starts with only the current access token') do
  source = contract.client
  contract.previous_session = source.current_session
  raise 'current session is missing' unless contract.previous_session

  contract.bootstrap_cleanup = contract.register_cleanup(-> { source.auth.sign_out })
  contract.client = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key'),
    access_token: contract.previous_session.access_token
  )
  contract.record { contract.client.current_session }
end

Then('the token-only session has no cached user') do
  session = contract.client.current_session
  raise 'token-only session is missing' unless session
  raise 'token-only session invented a user' unless session.user_id.nil? && session.user.nil?
end

When('a fresh client starts with a rejected access token') do
  contract.client = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key'),
    access_token: 'sdk-contract-rejected-access-token'
  )
  contract.previous_session = contract.client.current_session
  contract.record { contract.client.current_session }
end

Then('the session retains only the supplied access token') do
  session = contract.client.current_session
  raise 'token-only session is missing' unless session
  raise 'supplied access token changed' unless session.access_token == contract.previous_session.access_token
  raise 'token-only session invented a refresh token' unless session.refresh_token.nil?
end

When('the client signs out') do
  contract.signed_out_session = contract.client.auth.current_session
  raise 'current session is missing' unless contract.signed_out_session

  contract.record { contract.client.auth.sign_out }
  if contract.last_outcome.ok && contract.bootstrap_cleanup
    contract.remove_cleanup(contract.bootstrap_cleanup)
    contract.bootstrap_cleanup = nil
  end
end

When('a fresh client loads a profile with the signed-out access token') do
  target = Volcano::Client.new(
    api_url: contract.fixture.fetch('api_url'),
    anon_key: contract.fixture.fetch('anon_key'),
    access_token: contract.signed_out_session.access_token
  )
  contract.record { target.auth.user }
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

Then('the SDK operation fails') do
  raise 'SDK operation did not fail' unless contract.last_outcome && !contract.last_outcome.ok
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

Then('the auth-state listener observes the signed-in contract user') do
  expected_user_id = contract.fixture.fetch('user_id')
  observed = contract.auth_state_sessions.any? { |session| session&.user_id == expected_user_id }
  raise 'auth-state listener did not observe the contract user' unless observed
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

def query_fixture_table
  contract.client.database(contract.fixture.fetch('database_name')).from(contract.fixture.fetch('query_table_name'))
end

def query_fixture_filters(filters)
  contract.record do
    table = query_fixture_table
    filters.transform_values do |operator, column, value|
      table.select('slug').public_send(operator, column, value).order('rank').execute
    end
  end
end

When('the client selects a projected page of query fixture members') do
  contract.record do
    query_fixture_table.select('slug', 'rank').in('slug', %w[alpha beta gamma delta])
                       .order('enabled').order('rank', ascending: false).offset(1).limit(2).execute
  end
end

Then('the projected page contains only beta and gamma in that order') do
  expected = [{ 'slug' => 'beta', 'rank' => 20 }, { 'slug' => 'gamma', 'rank' => 30 }]
  raise 'projected page differs' unless contract.last_outcome.value == expected
end

When('the client selects query fixture rows with each comparison filter') do
  query_fixture_filters(neq: [:neq, 'rank', 20], gt: [:gt, 'rank', 20], gte: [:gte, 'rank', 20],
                        lt: [:lt, 'rank', 30], lte: [:lte, 'rank', 30])
end

Then('each comparison returns exactly the matching query fixture rows') do
  expected = {
    neq: %w[alpha gamma delta epsilon], gt: %w[gamma delta epsilon], gte: %w[beta gamma delta epsilon],
    lt: %w[alpha beta], lte: %w[alpha beta gamma]
  }.transform_values { |slugs| slugs.map { |slug| { 'slug' => slug } } }
  raise 'comparison results differ' unless contract.last_outcome.value == expected
end

When('the client selects query fixture rows with case-sensitive and insensitive patterns') do
  query_fixture_filters(like: [:like, 'label', 'Case_%'], ilike: [:ilike, 'label', 'case_%'])
end

Then('each pattern returns exactly the matching query fixture rows') do
  expected = { like: %w[alpha epsilon], ilike: %w[alpha beta epsilon] }
             .transform_values { |slugs| slugs.map { |slug| { 'slug' => slug } } }
  raise 'pattern results differ' unless contract.last_outcome.value == expected
end

When('the client selects query fixture rows with null and boolean filters') do
  query_fixture_filters(null: [:is, 'label', nil], enabled: [:is, 'enabled', true], disabled: [:is, 'enabled', false])
end

Then('each identity filter returns exactly the matching query fixture rows') do
  expected = { null: %w[gamma], enabled: %w[alpha gamma epsilon], disabled: %w[beta delta] }
             .transform_values { |slugs| slugs.map { |slug| { 'slug' => slug } } }
  raise 'identity results differ' unless contract.last_outcome.value == expected
end

When('the client inserts its contract row') do
  row = contract.fixture.fetch('mutation_rows').fetch('insert')
  contract.record do
    table = contract.client
                    .database(contract.fixture.fetch('database_name'))
                    .from(contract.fixture.fetch('table_name'))
    contract.register_cleanup(-> { table.delete.eq('slug', row.fetch('slug')).execute })
    table.insert(row).execute
  end
end

Then('exactly the inserted contract row is returned') do
  row = contract.fixture.fetch('mutation_rows').fetch('insert')
  raise 'database result did not match the inserted row' unless contract.last_outcome.value == [row]
end

When('the client updates its contract row') do
  row = contract.fixture.fetch('mutation_rows').fetch('update')
  contract.record do
    table = contract.client
                    .database(contract.fixture.fetch('database_name'))
                    .from(contract.fixture.fetch('table_name'))
    contract.register_cleanup(lambda do
      table.update('value' => row.fetch('before').fetch('value'))
           .eq('slug', row.fetch('before').fetch('slug'))
           .execute
    end)
    table.update('value' => row.fetch('after').fetch('value'))
         .eq('slug', row.fetch('before').fetch('slug'))
         .execute
  end
end

Then('exactly the updated contract row is returned') do
  row = contract.fixture.fetch('mutation_rows').fetch('update').fetch('after')
  raise 'database result did not match the updated row' unless contract.last_outcome.value == [row]
end

When('the client deletes its contract row') do
  row = contract.fixture.fetch('mutation_rows').fetch('delete')
  contract.record do
    table = contract.client
                    .database(contract.fixture.fetch('database_name'))
                    .from(contract.fixture.fetch('table_name'))
    contract.register_cleanup(lambda do
      table.delete.eq('slug', row.fetch('slug')).execute
      table.insert(row).execute
    end)
    table.delete.eq('slug', row.fetch('slug')).execute
  end
end

Then('exactly the deleted contract row is returned') do
  row = contract.fixture.fetch('mutation_rows').fetch('delete')
  raise 'database result did not match the deleted row' unless contract.last_outcome.value == [row]
end

When('the client updates a missing contract row') do
  contract.record do
    contract.client
            .database(contract.fixture.fetch('database_name'))
            .from(contract.fixture.fetch('table_name'))
            .update('value' => 'must-not-be-written')
            .eq('slug', "#{contract.fixture.fetch('fixture_row').fetch('slug')}-missing")
            .execute
  end
end

When('the client deletes a missing contract row') do
  contract.record do
    contract.client
            .database(contract.fixture.fetch('database_name'))
            .from(contract.fixture.fetch('table_name'))
            .delete
            .eq('slug', "#{contract.fixture.fetch('fixture_row').fetch('slug')}-missing")
            .execute
  end
end

Then('the mutation returns an empty row list') do
  raise 'mutation did not return an empty row list' unless contract.last_outcome.value == []
end

Then('the existing contract row is unchanged') do
  row = contract.fixture.fetch('fixture_row')
  result = contract.client
                   .database(contract.fixture.fetch('database_name'))
                   .from(contract.fixture.fetch('table_name'))
                   .select('*')
                   .eq('slug', row.fetch('slug'))
                   .execute
  raise 'existing contract row changed' unless result == [row]
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

When('the client uploads the contract object as text\/plain and reads its stored metadata') do
  contract.record do
    bucket = contract.client.storage.from(contract.fixture.fetch('bucket_name'))
    uploaded = bucket.upload(contract.storage_path, contract.storage_bytes, content_type: 'text/plain')
    contract.register_cleanup(-> { bucket.remove(contract.storage_path) })
    listed = bucket.list(contract.storage_path)
    {
      'path' => uploaded.fetch('name'),
      'bytes' => bucket.download(contract.storage_path),
      'content_type' => uploaded.fetch('mime_type'),
      'listed' => listed.objects.map { |item| { 'name' => item.name, 'mime_type' => item.mime_type } }
    }
  end
end

Then('the uploaded and listed object content types are text\/plain') do
  value = contract.last_outcome.value
  raise 'upload content type changed' unless value.fetch('content_type') == 'text/plain'

  expected = [{ 'name' => contract.storage_path, 'mime_type' => 'text/plain' }]
  raise 'stored content type changed' unless value.fetch('listed') == expected
end

When('the client uploads the contract object and downloads bytes 2 through 7') do
  contract.record do
    bucket = contract.client.storage.from(contract.fixture.fetch('bucket_name'))
    uploaded = bucket.upload(contract.storage_path, contract.storage_bytes)
    contract.register_cleanup(-> { bucket.remove(contract.storage_path) })
    {
      'bytes' => bucket.download(contract.storage_path, range: 'bytes=2-7'),
      'path' => uploaded.fetch('name')
    }
  end
end

Then('the downloaded bytes equal uploaded bytes 2 through 7 inclusive') do
  expected = contract.storage_bytes.byteslice(2, 6)
  raise 'downloaded range changed' unless contract.last_outcome.value.fetch('bytes') == expected
end

When('the client copies, moves, and removes a copy of the contract object') do
  bucket = contract.client.storage.from(contract.fixture.fetch('bucket_name'))
  source = contract.storage_path
  copied = "#{source}.copy"
  moved = "#{source}.moved"
  [source, copied, moved].each do |path|
    contract.register_cleanup(lambda do
      bucket.remove(path) if bucket.list(path).objects.any? { |item| item.name == path }
    end)
  end
  contract.record do
    bucket.upload(source, contract.storage_bytes)
    bucket.copy(source, copied)
    original_bytes = bucket.download(source)
    copied_bytes = bucket.download(copied)
    bucket.move(copied, moved)
    moved_bytes = bucket.download(moved)
    after_move = bucket.list(source).objects.map(&:name).sort
    bucket.remove(moved)
    after_remove = bucket.list(source).objects.map(&:name).sort
    remaining_bytes = bucket.download(source)
    {
      'bytes' => [original_bytes, copied_bytes, moved_bytes, remaining_bytes],
      'after_move' => after_move,
      'after_remove' => after_remove
    }
  end
end

Then('the original, copied, and moved bytes equal the uploaded bytes') do
  raise 'storage lifecycle changed bytes' unless contract.last_outcome.value.fetch('bytes').all?(contract.storage_bytes)
end

Then('moving the copy leaves only the original and moved paths') do
  expected = [contract.storage_path, "#{contract.storage_path}.moved"].sort
  raise 'move left unexpected paths' unless contract.last_outcome.value.fetch('after_move') == expected
end

Then('removing the moved object leaves the original unchanged') do
  value = contract.last_outcome.value
  raise 'remove left unexpected paths' unless value.fetch('after_remove') == [contract.storage_path]
  raise 'remove changed original bytes' unless value.fetch('bytes').fetch(3) == contract.storage_bytes
end

def storage_contract_bucket
  contract.client.storage.from(contract.fixture.fetch('bucket_name'))
end

def clean_storage_contract_object
  bucket = storage_contract_bucket
  bucket.remove(contract.storage_path) if bucket.list(contract.storage_path).objects.any? do |item|
    item.name == contract.storage_path
  end
end

def register_storage_session_cleanup(bucket, session)
  contract.register_cleanup(lambda do
    bucket.abort_upload_session(contract.storage_path, session_id: session.session_id)
  rescue Volcano::Error::NotFoundError
    nil
  end)
  contract.register_cleanup(-> { clean_storage_contract_object })
end

def start_storage_session(bucket, bytes)
  session = bucket.create_upload_session(
    contract.storage_path, total_size: bytes.bytesize,
                           part_size: 5 * 1024 * 1024, content_type: 'application/octet-stream'
  )
  register_storage_session_cleanup(bucket, session)
  session
end

def partial_storage_upload
  bucket = storage_contract_bucket
  bytes = ('x' * (5 * 1024 * 1024)).b + contract.storage_bytes
  session = start_storage_session(bucket, bytes)
  part = bucket.upload_part(contract.storage_path, session_id: session.session_id, part_number: 1,
                                                   data: bytes.byteslice(0, session.part_size))
  { 'session' => session, 'part' => part, 'bytes' => bytes }
end

When('the client uploads one part and resumes the contract upload') do
  contract.record do
    value = partial_storage_upload
    bucket = storage_contract_bucket
    session = value.fetch('session')
    value['progress'] = bucket.get_upload_session(contract.storage_path, session_id: session.session_id)
    bucket.upload_part(contract.storage_path, session_id: session.session_id, part_number: 2,
                                              data: value.fetch('bytes').byteslice(session.part_size..))
    value['object'] = bucket.complete_upload_session(contract.storage_path, session_id: session.session_id)
    value['download'] = bucket.download(contract.storage_path)
    value
  end
end

Then('upload progress describes exactly the first uploaded part') do
  value = contract.last_outcome.value
  progress, session, part = value.values_at('progress', 'session', 'part')
  expected = { session_id: session.session_id, path: contract.storage_path,
               content_type: 'application/octet-stream', status: 'uploading',
               total_size: value.fetch('bytes').bytesize, part_size: 5 * 1024 * 1024, total_parts: 2,
               parts_uploaded: 1, bytes_uploaded: 5 * 1024 * 1024, parts: [part] }
  raise 'upload progress differs' unless progress.to_h.slice(*expected.keys) == expected
  raise 'session chunking differs' unless session.part_size == expected[:part_size] && session.total_parts == 2
  raise 'uploaded part differs' unless part.part_number == 1 && part.size == session.part_size && !part.etag.empty?
end

Then('the completed multipart object preserves its path, type, and bytes') do
  value = contract.last_outcome.value
  expected = { name: contract.storage_path, mime_type: 'application/octet-stream', size: value.fetch('bytes').bytesize }
  raise 'completed metadata differs' unless value.fetch('object').to_h.slice(*expected.keys) == expected
  raise 'completed bytes differ' unless value.fetch('download') == value.fetch('bytes')
end

When('the client uploads one part and aborts the contract upload') do
  contract.record do
    session = partial_storage_upload.fetch('session')
    bucket = storage_contract_bucket
    bucket.abort_upload_session(contract.storage_path, session_id: session.session_id)
    {
      session: -> { bucket.get_upload_session(contract.storage_path, session_id: session.session_id) },
      object: -> { bucket.download(contract.storage_path) }
    }.transform_values do |read|
      read.call
      'unexpected success'
    rescue Volcano::Error::NotFoundError
      'not found'
    end
  end
end

Then('the aborted session and unfinished object are not found') do
  expected = { session: 'not found', object: 'not found' }
  raise 'aborted upload remains accessible' unless contract.last_outcome.value == expected
end

def anonymous_storage_read(url)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 10) do |http|
    http.get(uri.request_uri)
  end
end

When('the client makes the contract object public and private again') do
  contract.record do
    bucket = storage_contract_bucket
    contract.register_cleanup(-> { clean_storage_contract_object })
    bucket.upload(contract.storage_path, contract.storage_bytes)
    url = bucket.get_public_url(contract.storage_path)
    before = anonymous_storage_read(url)
    public_object = bucket.update_visibility(contract.storage_path, public: true)
    visible = anonymous_storage_read(url)
    private_object = bucket.update_visibility(contract.storage_path, public: false)
    after = anonymous_storage_read(url)
    { statuses: [before.code, visible.code, after.code], bytes: visible.body.b,
      visibility: [public_object.is_public, private_object.is_public],
      private_bytes: [before.body.to_s.b, after.body.to_s.b] }
  end
end

Then('anonymous reads return the original bytes only while the object is public') do
  expected = { statuses: %w[404 200 404], bytes: contract.storage_bytes, visibility: [true, false] }
  value = contract.last_outcome.value
  if value.fetch(:private_bytes).any? { |body| body.include?(contract.storage_bytes) }
    raise 'private response leaked bytes'
  end
  raise 'anonymous visibility differs' unless value.slice(*expected.keys) == expected
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

When('the client recovers the contract lock with caller-owned tokens') do
  contract.record do
    locks = contract.service_client.locks
    key = contract.lock_key
    token = SecureRandom.uuid
    request_id = SecureRandom.uuid
    lease = locks.acquire(key, ttl: 30, token: token, request_id: request_id)
    cleanup = contract.register_lock_cleanup(key, lease)
    recovered = locks.acquire(key, ttl: 30, token: token, request_id: request_id)
    held = locks.get(key, request_id: SecureRandom.uuid)
    renewed = locks.renew(key, recovered, ttl: 60, request_id: SecureRandom.uuid)
    locks.release(key, renewed, request_id: SecureRandom.uuid)
    available = locks.get(key, request_id: SecureRandom.uuid)
    { 'token' => token, 'cleanup' => cleanup, 'lease' => lease, 'recovered' => recovered, 'held' => held,
      'renewed' => renewed, 'available' => available }
  end
end

Then('recovery and renewal preserve the held lease until release') do
  value = contract.last_outcome.value
  raise 'recovered lease is not held' unless value.fetch('held').held
  raise 'released lease is still held' if value.fetch('available').held

  contract.remove_cleanup(value.fetch('cleanup'))

  leases = value.values_at('lease', 'recovered', 'renewed')
  raise 'ownership token changed' unless leases.all? { |lease| lease.token == value.fetch('token') }

  fences = [*leases, value.fetch('held')].map(&:fencing_token)
  raise 'fencing token changed or missing' unless fences.first && fences.uniq.length == 1
end

When('the client acquires and force releases the contract lock') do
  contract.record do
    locks = contract.service_client.locks
    lease = locks.acquire(contract.lock_key, ttl: 30)
    cleanup = contract.register_lock_cleanup(contract.lock_key, lease)
    locks.force_release(contract.lock_key, request_id: SecureRandom.uuid)
    { 'lease' => lease, 'cleanup' => cleanup, 'available' => locks.get(contract.lock_key) }
  end
end

Then('the force-released lock is available') do
  value = contract.last_outcome.value
  raise 'force-released lease is still held' if value.fetch('available').held

  contract.remove_cleanup(value.fetch('cleanup'))
end

When('the client reacquires the force-released contract lock') do
  original = contract.last_outcome.value.fetch('lease')
  contract.record do
    replacement = contract.service_client.locks.acquire(contract.lock_key, ttl: 30)
    contract.register_lock_cleanup(contract.lock_key, replacement)
    { 'original' => original, 'replacement' => replacement }
  end
end

Then('the replacement owner receives a higher fencing token') do
  original, replacement = contract.last_outcome.value.fetch_values('original', 'replacement')
  raise 'new acquisition reused the ownership token' if original.token == replacement.token
  raise 'original fencing token is missing' unless original.fencing_token
  raise 'replacement fencing token did not advance' unless replacement.fencing_token > original.fencing_token
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

Given('the client replaces its access token with a rejected token') do
  session = contract.client.auth.current_session
  raise 'current session is missing' unless session

  parts = session.access_token.split('.')
  raise 'access token has no session claims' unless parts.length == 3

  rejected = [parts[0], parts[1], 'sdk-contract-rejected-signature'].join('.')
  contract.previous_session = Volcano::Session.new(
    access_token: rejected,
    refresh_token: session.refresh_token,
    user_id: session.user_id
  )
  contract.client.auth.current_session = contract.previous_session
end

['database read', 'storage operation', 'profile read', 'session list', 'function invocation'].each do |operation|
  Then("the #{operation} replaces the rejected token for the same user") do
    session = contract.client.auth.current_session
    raise 'current session is missing' unless session
    raise 'access token is missing' if session.access_token.to_s.empty?
    raise 'access token was not replaced' if session.access_token == contract.previous_session.access_token
    raise 'refresh token is missing' if session.refresh_token.to_s.empty?
    raise 'session has the wrong user' unless session.user_id == contract.fixture.fetch('user_id')
  end
end

When('one client pauses delivery for 1 second and then resumes with the same handler') do
  raise contract.last_outcome.error if contract.last_outcome && !contract.last_outcome.ok

  contract.record do
    Async do |task|
      VolcanoContract::BroadcastPause.new(contract).run(task)
    ensure
      contract.realtime_clients.reverse_each { |client| client.realtime.disconnect }
    end.wait
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

When('the authenticated client invokes the contract function by name') do
  contract.record do
    contract.client.functions.invoke(
      contract.fixture.fetch('function_name'), { 'value' => 'contract' }
    )
  end
end

When('the client invokes the contract function by name') do
  contract.record do
    contract.service_client.functions.invoke(
      contract.fixture.fetch('function_name'), { 'value' => 'contract' }
    )
  end
end

# The function is reachable only at the endpoint the platform resolved, on a
# domain the API URL does not name, so an echo coming back is what proves the
# SDK sent the request there rather than somewhere it guessed.
Then('the function echoes the payload') do
  response = contract.last_outcome.value
  raise "function returned #{response.status}" unless response.status == 200
  raise "function echoed #{response.data.inspect}" unless response.data == { 'echoed' => 'contract' }
end

When('the client lists its server sessions') do
  contract.record { contract.client.auth.list_sessions(page: 1, limit: 100) }
end

Then('the session list contains the current session for the contract user') do
  page = contract.last_outcome.value
  raise 'expected first session page' unless page.page == 1
  raise 'missing server sessions' unless page.total >= page.sessions.length && !page.sessions.empty?
  raise 'session has the wrong user' unless page.sessions.all? do |session|
    session.user_id == contract.fixture.fetch('user_id')
  end
  raise 'current session is missing or duplicated' unless page.sessions.one?(&:is_current)
end

When('the client loads its server-validated profile') do
  contract.record { contract.client.auth.user }
end

Then('the returned and cached profiles belong to the contract user') do
  expected = contract.fixture.fetch('user_id')
  raise 'profile belongs to another user' unless contract.last_outcome.value.id == expected
  raise 'cached profile belongs to another user' unless contract.client.current_session.user.fetch('id') == expected
end

Given('a read-only project logs client') do
  @logs_contract = VolcanoContract::Logs.new(contract)
end

When('the contract function emits three unique structured log events') do
  @logs_contract.emit(3)
end

When('the contract function emits one unique structured log event') do
  @logs_contract.emit(1)
end

When('the client searches and paginates those events within 240 seconds') do
  contract.record { @logs_contract.search }
end

When('the client reads matching log activity within 120 seconds') do
  contract.record { @logs_contract.activity }
end

Then('all three structured events retain their metadata without duplicates') do
  @logs_contract.verify_events(contract.last_outcome.value)
end

Then('activity counts exactly that event in its function and level buckets') do
  @logs_contract.verify_activity(contract.last_outcome.value)
end

When('one presence client joins and leaves while the other remains subscribed') do
  raise contract.last_outcome.error if contract.last_outcome && !contract.last_outcome.ok

  contract.record do
    Async do |task|
      VolcanoContract::PresenceMembership.new(contract).run(task)
    ensure
      contract.realtime_clients.reverse_each { |client| client.realtime.disconnect }
    end.wait
  end
end

Then('both rosters identify the contract user and the original handler observes membership changes') do
  raise 'presence membership did not match' unless contract.last_outcome.value == [1, 2, 1]
end

When('the clients observe an inserted and updated contract row') do
  raise contract.last_outcome.error if contract.last_outcome && !contract.last_outcome.ok

  contract.record do
    Async do |task|
      VolcanoContract::PostgresChanges.new(contract).run(task)
    ensure
      contract.realtime_clients.reverse_each { |client| client.realtime.disconnect }
    end.wait
  end
end

Then('automatic and lightweight notifications retain metadata and row identity') do
  raise 'Postgres notification values changed' unless contract.last_outcome.value == %w[INSERT UPDATE]
end
