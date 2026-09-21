# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  def realtime_client(socket, transport: SpecSupport::RealtimeAuthTransport.new)
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: transport,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    client
  end

  def presence_info(client, user, display_name)
    {
      'client' => client,
      'user' => user,
      'conn_info' => { 'user_metadata' => { 'display_name' => display_name } }
    }
  end

  def presence_reply(socket, clients)
    lambda do |command|
      next unless command.key?('presence')

      socket.respond(command.fetch('id'), result: { 'presence' => clients })
      :defer
    end
  end

  it 'sends commands while the socket reader is blocked waiting for data' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.subscribe
      task.yield
      expect(socket.reading).to be true

      task.with_timeout(0.2) do
        channel.unsubscribe
        channel.subscribe
        channel.send(event: 'message', value: 'after resume')
      end
      expect(socket.commands.map { |command| (command.keys - ['id']).first }).to eq(
        %w[connect subscribe unsubscribe subscribe publish]
      )
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'exposes the canonical channel name' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new)

    expect(client.realtime.channel('contract').name).to eq('broadcast:contract')
    expect(client.realtime.channel('contract').name).to be_frozen
    expect(client.realtime.channel('lobby', type: :presence).name).to eq('presence:lobby')
    expect(client.realtime.channel('public:messages', type: :postgres).name).to eq(
      'postgres:public:messages'
    )
    expect { client.realtime.channel('bad', type: :unknown) }.to raise_error(
      ArgumentError,
      'unsupported realtime channel type: unknown'
    )
  end

  it 'routes immutable RLS-scoped Postgres changes by event, schema, and table' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    updates = []
    inserts = []

    Async do |task|
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('UPDATE', schema: 'public', table: 'messages') do |change|
        updates << change
      end
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        inserts << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages',
          'record' => { 'id' => 1, 'body' => 'updated' },
          'old_record' => { 'id' => 1, 'body' => 'old' },
          'columns' => ['body'], 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { task.yield until updates.any? }

      expect(updates.fetch(0)).to have_attributes(
        type: 'UPDATE', schema: 'public', table: 'messages',
        record: { 'id' => 1, 'body' => 'updated' },
        old_record: { 'id' => 1, 'body' => 'old' },
        columns: ['body'], timestamp: '2026-09-02T12:00:00Z'
      )
      expect(updates.fetch(0).record).to be_frozen
      expect(updates.fetch(0).columns).to be_frozen
      expect(inserts).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'does not overmatch malformed or different Postgres publication channels' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    received = []

    Async do |task|
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('*', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      payload = {
        'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
        'record' => { 'id' => 1 }, 'timestamp' => '2026-09-02T12:00:00Z'
      }
      socket.publication(channel: 'project-id:postgres:public:other:user-id', data: payload)
      socket.publication(channel: 'postgres:public:messages', data: payload)
      socket.publication(channel: 'project-id:postgres:public:messages', data: payload)
      socket.publication(
        channel: 'project-id:postgres:public:messages:extra:user-id', data: payload
      )
      task.sleep(0.01)

      expect(received).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'preserves lightweight Postgres metadata when a full row is unavailable' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    received = []

    Async do |task|
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { task.yield until received.any? }

      expect(received.fetch(0)).to have_attributes(id: 42, mode: 'lightweight', record: nil)
      client.realtime.disconnect
    end.wait
  end

  it 'fetches a full Postgres row for a lightweight insert' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      reactor_thread = Thread.current
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      change = task.with_timeout(0.2) { received.dequeue }

      expect(change).to have_attributes(
        record: { 'id' => 42, 'body' => 'fetched' }, id: nil, mode: nil
      )
      expect(transport.queries).to contain_exactly(
        authorization: 'access-token',
        database_name: 'app',
        body: {
          'table' => 'messages',
          'filters' => [{ 'column' => 'id', 'operator' => 'in', 'value' => [42] }]
        }
      )
      expect(transport.query_threads).not_to include(reactor_thread)
      client.realtime.disconnect
    end.wait
  end

  it 'batches lightweight row lookups and preserves duplicate deliveries' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new(
      [
        { 'id' => 2, 'body' => 'second' },
        { 'id' => 1, 'body' => 'first' }
      ]
    )
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      [1, 1, 2].each do |id|
        socket.publication(
          channel: 'project-id:postgres:public:messages:user-id',
          data: {
            'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
            'id' => id, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
          }
        )
      end
      changes = Array.new(3) { task.with_timeout(0.2) { received.dequeue } }

      expect(changes.map { |change| change.record.fetch('id') }).to eq([1, 1, 2])
      expect(transport.queries).to contain_exactly(
        authorization: 'access-token',
        database_name: 'app',
        body: {
          'table' => 'messages',
          'filters' => [{ 'column' => 'id', 'operator' => 'in', 'value' => [1, 2] }]
        }
      )
      client.realtime.disconnect
    end.wait
  end

  it 'limits a row lookup batch to 50 changes' do
    socket = SpecSupport::FacadeSocket.new
    rows = Array.new(51) { |index| { 'id' => index + 1 } }
    transport = SpecSupport::RealtimeDatabaseTransport.new(rows)
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      rows.each do |row|
        socket.publication(
          channel: 'project-id:postgres:public:messages:user-id',
          data: {
            'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
            'id' => row.fetch('id'), 'mode' => 'lightweight',
            'timestamp' => '2026-09-02T12:00:00Z'
          }
        )
      end
      changes = Array.new(51) { task.with_timeout(0.2) { received.dequeue } }

      expect(changes.map { |change| change.record.fetch('id') }).to eq((1..51).to_a)
      query_ids = transport.queries.map { |query| query.dig(:body, 'filters', 0, 'value') }
      expect(query_ids.flatten).to eq((1..51).to_a)
      expect(query_ids.map(&:length)).to all(be <= 50)
      client.realtime.disconnect
    end.wait
  end

  it 'supports a per-channel row lookup batch size' do
    socket = SpecSupport::FacadeSocket.new
    rows = Array.new(3) { |index| { 'id' => index + 1 } }
    transport = SpecSupport::RealtimeDatabaseTransport.new(rows)
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel(
        'public:messages', type: :postgres, fetch_max_batch_size: 2
      )
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      rows.each do |row|
        socket.publication(
          channel: 'project-id:postgres:public:messages:user-id',
          data: {
            'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
            'id' => row.fetch('id'), 'mode' => 'lightweight',
            'timestamp' => '2026-09-02T12:00:00Z'
          }
        )
      end
      Array.new(3) { task.with_timeout(0.2) { received.dequeue } }

      expect(transport.queries.map { |query| query.dig(:body, 'filters', 0, 'value') }).to eq(
        [[1, 2], [3]]
      )
      client.realtime.disconnect
    end.wait
  end

  it 'validates and preserves cached channel fetch settings' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new)
    channel = client.realtime.channel(
      'public:messages',
      type: :postgres,
      fetch_batch_window_ms: 10,
      fetch_max_batch_size: 25
    )

    expect(
      client.realtime.channel(
        'public:messages',
        type: :postgres,
        fetch_batch_window_ms: 10,
        fetch_max_batch_size: 25
      )
    ).to equal(channel)
    expect do
      client.realtime.channel(
        'public:messages',
        type: :postgres,
        fetch_batch_window_ms: 20,
        fetch_max_batch_size: 25
      )
    end.to raise_error(ArgumentError, 'conflicting fetch options for postgres:public:messages')
    expect do
      client.realtime.channel(
        'other', type: :postgres, fetch_batch_window_ms: 0
      )
    end.to raise_error(ArgumentError, 'fetch_batch_window_ms must be a positive integer')
    expect do
      client.realtime.channel(
        'other', type: :postgres, fetch_max_batch_size: 129
      )
    end.to raise_error(ArgumentError, 'fetch_max_batch_size must be between 1 and 128')
  end

  it 'auto-fetches lightweight changes for wildcard Postgres listeners' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('*', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )

      expect(task.with_timeout(0.2) { received.dequeue }.record).to eq(
        'id' => 42, 'body' => 'fetched'
      )
      client.realtime.disconnect
    end.wait
  end

  it 'expands lightweight deletes locally without querying a vanished row' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('DELETE', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'DELETE', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      change = task.with_timeout(0.2) { received.dequeue }

      expect(change).to have_attributes(old_record: { 'id' => 42 }, id: nil, mode: nil)
      expect(transport.queries).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'queries the schema carried by a lightweight Postgres change' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('audit:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'audit', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:audit:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'audit', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { received.dequeue }

      expect(transport.queries.dig(0, :body, 'table')).to eq('audit.messages')
      client.realtime.disconnect
    end.wait
  end

  it 'does not query changes without a matching Postgres listener' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') { nil }
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.sleep(0.01)

      expect(transport.queries).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'rejects conflicting auto-fetch options for a cached channel' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new)
    channel = client.realtime.channel('public:messages', type: :postgres)

    expect do
      client.realtime.channel('public:messages', type: :postgres, auto_fetch: false)
    end.to raise_error(ArgumentError, 'conflicting auto_fetch option for postgres:public:messages')
    expect(client.realtime.channel('public:messages', type: :postgres)).to equal(channel)
  end

  it 'delivers Postgres changes to an unfiltered on callback' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)

    Async do |task|
      received = Async::Queue.new
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on('*') { |change| received.enqueue(change) }
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'record' => { 'id' => 42 }, 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )

      expect(task.with_timeout(0.2) { received.dequeue }.record).to eq('id' => 42)
      client.realtime.disconnect
    end.wait
  end

  it 'reports auto-fetch failures and delivers the lightweight change' do
    socket = SpecSupport::FacadeSocket.new
    error = Volcano::Error::TransportError.new('database unavailable')
    transport = SpecSupport::RealtimeDatabaseTransport.new(error: error)
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      reported = Async::Queue.new
      client.realtime.on_error { |context| reported.enqueue(context) }
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      change = task.with_timeout(0.2) { received.dequeue }
      context = task.with_timeout(0.2) { reported.dequeue }

      expect(change).to have_attributes(record: nil, id: 42, mode: 'lightweight')
      expect(context).to have_attributes(message: 'database unavailable')
      client.realtime.disconnect
    end.wait
  end

  it 'preserves publication order while a lightweight fetch is pending' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = []
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('*', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages',
          'record' => { 'id' => 43 }, 'timestamp' => '2026-09-02T12:00:01Z'
        }
      )
      task.sleep(0.01)
      expect(received).to be_empty

      transport.release.enqueue(true)
      task.with_timeout(0.2) { task.yield until received.length == 2 }
      expect(received.map(&:type)).to eq(%w[INSERT UPDATE])
      client.realtime.disconnect
    end.wait
  end

  it 'waits for a running fetch and invalidates it during unsubscribe' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = []
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      unsubscribe = task.async { channel.unsubscribe }
      task.yield
      expect(unsubscribe).to be_running

      transport.release.enqueue(true)
      task.with_timeout(0.2) { unsubscribe.wait }
      expect(received).to be_empty

      channel.subscribe
      transport.release.enqueue(true)
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:01Z'
        }
      )
      task.with_timeout(0.2) { task.yield until received.length == 1 }
      expect(received.fetch(0).record).to eq('id' => 42, 'body' => 'fetched')
      client.realtime.disconnect
    end.wait
  end

  it 'waits for a running fetch during disconnect' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = []
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      disconnect = task.async { client.realtime.disconnect }
      task.yield
      expect(disconnect).to be_running

      transport.release.enqueue(true)
      task.with_timeout(0.2) { disconnect.wait }
      expect(received).to be_empty
    end.wait
  end

  it 'uses a refreshed token for subsequent changes from the same user' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      client.store_session(
        Volcano::Session.new(
          access_token: 'access-refreshed', refresh_token: 'refresh-token', user_id: 'user-123'
        ),
        event: :token_refreshed
      )
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { received.dequeue }

      expect(transport.queries.dig(0, :authorization)).to eq('access-refreshed')
      client.realtime.disconnect
    end.wait
  end

  [false, true].each do |same_session|
    it "binds bootstrap realtime without a profile preflight, same session: #{same_session}" do
      token = lambda do |session_id|
        "header.#{[{ session_id: session_id }.to_json].pack('m0').tr('+/', '-_').delete('=')}.signature"
      end
      session_a = '00000000-0000-4000-8000-000000000001'
      session_b = '00000000-0000-4000-8000-000000000002'
      socket = SpecSupport::FacadeSocket.new
      transport = instance_double(Volcano.const_get(:GeneratedTransport, false))
      allow(transport).to receive(:auth_refresh).and_return(
        Volcano::Transport::Response.new(status: 200, headers: {}, data: nil,
                                         body: { 'access_token' => token.call(same_session ? session_a : session_b),
                                                 'refresh_token' => 'rotated', 'user' => { 'id' => 'user-123' } })
      )
      client = Volcano::Client.new(anon_key: 'anon', access_token: token.call(session_a), refresh_token: 'refresh',
                                   _transport: transport, _realtime_socket_factory: ->(_address) { socket })
      Async do
        client.realtime.channel('contract').subscribe
        expect(client.current_session.user_id).to be_nil
        if same_session
          client.auth.refresh_session
          client.realtime.channel('another').subscribe
        else
          expect { client.auth.refresh_session }
            .to raise_error(Volcano::Error::AuthenticationError, /different server session/)
        end
        expect(client.current_session.access_token).to eq(token.call(session_a))
      ensure
        client.realtime.disconnect
      end.wait
    end
  end

  it 'keeps a token-only connection usable after its profile establishes the user identity' do
    socket = SpecSupport::FacadeSocket.new
    transport = instance_double(Volcano.const_get(:GeneratedTransport, false))
    allow(transport).to receive_messages(
      auth_get_user: Volcano::Transport::Response.new(
        status: 200, body: { 'user' => { 'id' => 'user-123', 'email' => 'u@example.com', 'status' => 'active' } },
        headers: {}, data: nil
      ),
      query_database_select: Volcano::Transport::Response.new(
        status: 200, body: { 'data' => [{ 'id' => 42, 'body' => 'fetched' }] }, headers: {}, data: nil
      )
    )
    client = Volcano::Client.new(anon_key: 'anon', access_token: 'access-token', _transport: transport,
                                 _realtime_socket_factory: ->(_address) { socket })
    Async do |task|
      broadcast = client.realtime.channel('contract')
      broadcast.subscribe
      client.auth.user
      broadcast.unsubscribe
      expect { broadcast.subscribe }.not_to raise_error
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') { |change| received.enqueue(change) }
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      expect(task.with_timeout(0.2) { received.dequeue }.record).to eq('id' => 42, 'body' => 'fetched')
      expect(transport).to have_received(:query_database_select).with(hash_including(authorization: 'access-token'))
      client.realtime.disconnect
    end.wait
  end

  it 'preserves a queued change when the same user refreshes their token' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      client.store_session(
        Volcano::Session.new(
          access_token: 'access-refreshed', refresh_token: 'refresh-token', user_id: 'user-123'
        ),
        event: :token_refreshed
      )
      transport.release.enqueue(true)

      expect(task.with_timeout(0.2) { received.dequeue }.record).to eq(
        'id' => 42, 'body' => 'fetched'
      )
      client.realtime.disconnect
    end.wait
  end

  it 'uses the refreshed token for a queued row lookup' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      change = {
        'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
        'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
      }
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id', data: change
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id', data: change
      )
      client.store_session(
        Volcano::Session.new(
          access_token: 'access-refreshed', refresh_token: 'refresh-token', user_id: 'user-123'
        ),
        event: :token_refreshed
      )
      transport.release.enqueue(true)
      task.with_timeout(0.2) { transport.started.dequeue }
      transport.release.enqueue(true)
      2.times { task.with_timeout(0.2) { received.dequeue } }

      expect(transport.queries.map { |query| query.fetch(:authorization) }).to eq(
        %w[access-token access-refreshed]
      )
      client.realtime.disconnect
    end.wait
  end

  it 'does not block publication dispatch when a delivery queue is full' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::FirstBlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      reported = Async::Queue.new
      client.realtime.on_error { |context| reported.enqueue(context) }
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') { nil }
      channel.subscribe
      change = {
        'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
        'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
      }
      channel.__send__(:dispatch_postgres_change, change)
      task.with_timeout(0.2) { transport.started.dequeue }
      producer = task.async do
        129.times { channel.__send__(:dispatch_postgres_change, change) }
      end

      expect { task.with_timeout(0.2) { producer.wait } }.not_to raise_error
      expect(task.with_timeout(0.2) { reported.dequeue }.error).to be_a(
        Volcano::Realtime::PendingLimitError
      )
      transport.release.enqueue(true)
      client.realtime.disconnect
    end.wait
  end

  it 'discards a queued change after a new same-user session is adopted' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = []
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      client.store_session(
        Volcano::Session.new(
          access_token: 'new-access', refresh_token: 'new-refresh', user_id: 'user-123'
        )
      )
      transport.release.enqueue(true)
      task.sleep(0.01)

      expect(received).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'rejects a Postgres subscription when the socket belongs to another user' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)

    Async do
      client.realtime.channel('events').subscribe
      client.store_session(
        Volcano::Session.new(
          access_token: 'other-access', refresh_token: 'other-refresh', user_id: 'other-user'
        )
      )
      changes = client.realtime.channel('public:messages', type: :postgres)

      expect { changes.subscribe }.to raise_error(Volcano::Error::SessionChangedError)
      client.realtime.disconnect
    end.wait
  end

  it 'validates the database name when configuring auto-fetch' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new)

    expect { client.realtime.database_name = 'Not Valid' }.to raise_error(
      ArgumentError, 'database name must match ^[a-z0-9_]+$ and contain at most 64 characters'
    )
  end

  it 'does not deliver queued changes after the authenticated user changes' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = []
      client.realtime.database_name = 'app'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received << change
      end
      channel.subscribe
      2.times do |index|
        socket.publication(
          channel: 'project-id:postgres:public:messages:user-id',
          data: {
            'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
            'id' => index + 1, 'mode' => 'lightweight',
            'timestamp' => "2026-09-02T12:00:0#{index}Z"
          }
        )
      end
      task.with_timeout(0.2) { transport.started.dequeue }
      client.store_session(
        Volcano::Session.new(
          access_token: 'other-access', refresh_token: 'other-refresh', user_id: 'other-user'
        )
      )
      transport.release.enqueue(true)
      task.sleep(0.01)

      expect(received).to be_empty
      expect(transport.queries.length).to eq(1)
      client.realtime.disconnect
    end.wait
  end

  it 'captures the database selected when a change arrives' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::BlockingRealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app_one'
      channel = client.realtime.channel('public:messages', type: :postgres)
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      task.with_timeout(0.2) { transport.started.dequeue }
      client.realtime.database_name = 'app_two'
      transport.release.enqueue(true)
      task.with_timeout(0.2) { received.dequeue }

      expect(transport.queries.dig(0, :database_name)).to eq('app_one')
      client.realtime.disconnect
    end.wait
  end

  it 'can disable lightweight Postgres auto-fetch per channel' do
    socket = SpecSupport::FacadeSocket.new
    transport = SpecSupport::RealtimeDatabaseTransport.new
    client = realtime_client(socket, transport: transport)

    Async do |task|
      received = Async::Queue.new
      client.realtime.database_name = 'app'
      channel = client.realtime.channel(
        'public:messages', type: :postgres, auto_fetch: false
      )
      channel.on_postgres_changes('INSERT', schema: 'public', table: 'messages') do |change|
        received.enqueue(change)
      end
      channel.subscribe
      socket.publication(
        channel: 'project-id:postgres:public:messages:user-id',
        data: {
          'type' => 'INSERT', 'schema' => 'public', 'table' => 'messages',
          'id' => 42, 'mode' => 'lightweight', 'timestamp' => '2026-09-02T12:00:00Z'
        }
      )
      change = task.with_timeout(0.2) { received.dequeue }

      expect(change).to have_attributes(record: nil, id: 42, mode: 'lightweight')
      expect(transport.queries).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'validates Postgres change registrations' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new)
    callback = proc {}

    expect do
      client.realtime.channel('contract').on_postgres_changes(
        '*', schema: 'public', table: 'messages', &callback
      )
    end.to raise_error(ArgumentError, 'operation is only available for postgres channels')
    expect do
      client.realtime.channel('public:messages', type: :postgres).on_postgres_changes(
        'UPSERT', schema: 'public', table: 'messages', &callback
      )
    end.to raise_error(ArgumentError, 'unsupported postgres change event: UPSERT')
  end

  it 'delivers only message publications on presence channels without changing presence state' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    socket.on_write = presence_reply(socket, 'alice-client' => alice)

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      received = Async::Queue.new
      joins = []
      channel.on('join') { |data| joins << data }
      channel.on('message') { |data| received.enqueue(data) }
      channel.subscribe
      initial_state = channel.presence_state
      socket.publication(channel: 'project:presence:lobby', data: { 'event' => 'join' })
      message = { 'event' => 'message', 'value' => 'hello' }
      socket.publication(channel: 'project:presence:lobby', data: message)

      expect(task.with_timeout(1) { received.dequeue }).to eq(message)
      expect(received).to be_empty
      expect(joins).to be_empty
      expect(channel.presence_state).to equal(initial_state)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'rejects non-hash presence tracking without replacing the tracked snapshot' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe
      channel.track('status' => 'online')
      snapshot = channel.tracked_state

      expect { channel.track(['offline']) }.to raise_error(ArgumentError, 'presence state must be a hash')
      expect(channel.tracked_state).to equal(snapshot)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'preserves connection and user identities from typed presence replies' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    socket.on_write = presence_reply(socket, 'alice-client' => alice)

    Async do
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe

      expect(channel.presence_state).to eq(
        'alice-client' => Volcano::Realtime::PresenceInfo.new(
          client: 'alice-client', user: 'alice', data: alice.fetch('conn_info')
        )
      )
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'tracks an immutable presence snapshot through sync, join, leave, and unsubscribe', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    bob = presence_info('bob-client', 'bob', 'Bob')
    socket.on_write = presence_reply(socket, 'alice-client' => alice)

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      states = []
      joins = []
      leaves = []
      channel.on_presence_sync { |state| states << state }
      channel.on('join') { |info| joins << info }
      channel.on('leave') { |info| leaves << info }
      channel.subscribe
      tracked = { 'status' => ['online'] }
      channel.track(tracked)
      tracked.fetch('status') << 'away'
      socket.presence_event(channel: 'project:presence:lobby', event: 'join', info: bob)
      socket.presence_event(channel: 'project:presence:lobby', event: 'leave', info: alice)
      task.with_timeout(0.2) { task.yield until leaves.any? }

      expect(channel.get_presence_state.keys).to eq(['bob-client'])
      expect(joins.first).to eq(Volcano::Realtime::PresenceInfo.new(
                                  client: 'bob-client', user: 'bob', data: bob.fetch('conn_info')
                                ))
      expect(channel.tracked_state).to eq('status' => ['online'])
      expect { channel.tracked_state.fetch('status') << 'late' }.to raise_error(FrozenError)
      channel.unsubscribe
      expect(channel.get_presence_state).to be_empty
      expect(states.last).to be_empty
      expect { channel.track }.to raise_error(Volcano::Realtime::ClosedError, /not subscribed/)
      expect(client.realtime.remove_channel('lobby', type: :presence)).to be_nil
      client.realtime.disconnect
    end.wait
  end

  it 'applies join and leave pushes that arrive during presence synchronization' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    bob = presence_info('bob-client', 'bob', 'Bob')
    presence_commands = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('presence')

      presence_commands.enqueue(command)
      :defer
    end

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      subscribing = task.async { channel.subscribe }
      command = presence_commands.dequeue
      socket.presence_event(channel: 'project:presence:lobby', event: 'join', info: bob)
      socket.presence_event(channel: 'project:presence:lobby', event: 'leave', info: alice)
      socket.respond(command.fetch('id'), result: { 'presence' => { 'alice-client' => alice } })
      subscribing.wait
      task.with_timeout(0.2) { task.yield until channel.presence_state.keys == ['bob-client'] }

      expect(channel.presence_state.keys).to eq(['bob-client'])
      client.realtime.disconnect
    end.wait
  end

  it 'lets presence callbacks call channel methods without deadlocking' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      finished = Async::Queue.new
      channel.on_presence_sync do
        channel.track('status' => 'online')
        channel.unsubscribe
        finished.enqueue(true)
      end
      channel.subscribe

      expect(task.with_timeout(0.2) { finished.dequeue }).to be(true)
      expect(channel.tracked_state).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'ignores presence pushes captured before unsubscribe' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe
      channel.unsubscribe
      socket.presence_event(
        channel: 'project:presence:lobby',
        event: 'join',
        info: presence_info('late-client', 'late', 'Late')
      )
      task.yield

      expect(channel.presence_state).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'delivers unsubscribe presence sync outside the lifecycle lock' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      finished = Async::Queue.new
      channel.on_presence_sync do |state|
        next unless state.empty?

        begin
          channel.track('status' => 'online')
        rescue Volcano::Realtime::ClosedError
          finished.enqueue(true)
        end
      end
      channel.subscribe
      channel.unsubscribe

      expect(task.with_timeout(0.2) { finished.dequeue }).to be(true)
      client.realtime.disconnect
    end.wait
  end

  it 'does not emit a stale sync when a join callback unsubscribes' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      states = []
      channel.on_presence_sync { |state| states << state }
      channel.on('join') { channel.unsubscribe }
      channel.subscribe
      states.clear
      socket.presence_event(
        channel: 'project:presence:lobby', event: 'join',
        info: presence_info('bob-client', 'bob', 'Bob')
      )
      task.with_timeout(0.2) { task.yield until states.any? }

      expect(states).to all(be_empty)
      client.realtime.disconnect
    end.wait
  end

  it 'keeps a successful subscription usable when its initial presence query fails' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = lambda do |command|
      next unless command.key?('presence')

      socket.reject(command.fetch('id'), 'presence unavailable')
      :defer
    end

    Async do |task|
      errors = []
      client.realtime.on_error { |context| errors << context }
      channel = client.realtime.channel('lobby', type: :presence)
      expect(channel.subscribe).to be_nil
      task.with_timeout(0.2) { task.yield until errors.any? }
      expect(channel.unsubscribe).to be_nil
      expect(errors.first.message).to eq('presence unavailable')
      client.realtime.disconnect
    end.wait
  end

  it 'retains the last presence snapshot when a resync fails' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    socket.on_write = presence_reply(socket, 'alice-client' => alice)

    Async do |task|
      errors = []
      client.realtime.on_error { |context| errors << context }
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe
      socket.on_write = lambda do |command|
        next unless command.key?('presence')

        socket.reject(command.fetch('id'), 'resync unavailable')
        :defer
      end

      channel.__send__(:sync_presence, client.realtime.send(:protocol), 1)
      task.with_timeout(0.2) { task.yield until errors.any? }

      expect(channel.presence_state.keys).to eq(['alice-client'])
      client.realtime.disconnect
    end.wait
  end

  it 'reports one error when protocol loss rejects a presence resync' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      errors = []
      pending = Async::Queue.new
      client.realtime.on_error { |context| errors << context }
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe
      socket.on_write = lambda do |command|
        pending.enqueue(command) if command.key?('presence')
        :defer
      end
      syncing = task.async do
        channel.__send__(:sync_presence, client.realtime.send(:protocol), 1)
      end
      pending.dequeue

      socket.fail_read(IOError.new('socket failed'))
      syncing.wait
      task.with_timeout(0.2) { task.yield until errors.any? }

      expect(errors.length).to eq(1)
      client.realtime.disconnect
    end.wait
  end

  it 'clears presence after an unexpected disconnect' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    alice = presence_info('alice-client', 'alice', 'Alice')
    socket.on_write = presence_reply(socket, 'alice-client' => alice)

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      channel.subscribe
      expect(channel.presence_state).not_to be_empty
      socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) { task.yield until channel.presence_state.empty? }

      expect(channel.presence_state).to be_empty
      client.realtime.disconnect
    end.wait
  end

  it 'isolates failing join callbacks and still emits the resulting sync' do
    socket = SpecSupport::FacadeSocket.new
    client = realtime_client(socket)
    socket.on_write = presence_reply(socket, {})

    Async do |task|
      channel = client.realtime.channel('lobby', type: :presence)
      joins = []
      states = []
      channel.on('join') { raise 'callback failed' }
      channel.on('join') { |info| joins << info.client }
      channel.on_presence_sync { |state| states << state }
      channel.subscribe
      socket.presence_event(
        channel: 'project:presence:lobby',
        event: 'join',
        info: presence_info('bob-client', 'bob', 'Bob')
      )
      task.with_timeout(0.2) { task.yield until states.last&.key?('bob-client') }

      expect(joins).to eq(['bob-client'])
      expect(states.last.keys).to eq(['bob-client'])
      client.realtime.disconnect
    end.wait
  end

  it 'exposes the bounded async channel facade over Async::WebSocket::Client semantics', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    addresses = []
    factory = lambda do |address|
      addresses << address
      socket
    end
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: 'anon key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = []

    Async do
      channel = client.realtime.channel('contract')
      expect(channel.on('message') { |message| received << message }).to be(channel)
      expect(channel.subscribe).to be_nil
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 'contract' }
      )
      Async::Task.current.yield until received.any?
      expect(channel.send(event: 'message', value: 'contract')).to be_nil
      expect(channel.unsubscribe).to be_nil
      expect(client.realtime.disconnect).to be_nil
      expect { channel.send(event: 'message', value: 'again') }.to raise_error(
        Volcano::Realtime::ClosedError
      )
    end.wait

    expect(addresses).to eq(
      ['wss://api.test.volcano.dev/realtime/v1/websocket?apikey=anon%20key']
    )
    expect(received).to eq([{ 'event' => 'message', 'value' => 'contract' }])
    expect(socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe publish unsubscribe]
    )
    expect(socket.commands.map { |command| command.fetch('id') }).to eq([1, 2, 3, 4])
    expect(socket.commands.fetch(2).dig('publish', 'data')).to eq(
      'event' => 'message',
      'value' => 'contract'
    )
  end

  it 'reports connection lifecycle with immutable contexts', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    connected = []
    disconnected = []
    errors = []

    Async do |task|
      stop_connect = client.realtime.on_connect { |context| connected << context }
      client.realtime.on_disconnect { |context| disconnected << context }
      stop_error = client.realtime.on_error { |context| errors << context }

      client.realtime.channel('contract').subscribe
      task.with_timeout(0.2) { task.yield until connected.any? }
      expect(connected).to eq(
        [Volcano::Realtime::ConnectContext.new(client: 'client-123')]
      )
      expect(connected.first).to be_frozen
      expect(connected.first.client).to be_frozen

      stop_connect.call
      stop_connect.call
      stop_error.call
      client.realtime.disconnect
      task.with_timeout(0.2) { task.yield until disconnected.any? }
    end.wait

    expect(disconnected).to eq(
      [Volcano::Realtime::DisconnectContext.new(code: nil, reason: 'manual')]
    )
    expect(disconnected.first).to be_frozen
    expect(disconnected.first.reason).to be_frozen
    expect(errors).to be_empty
  end

  it 'reports transport errors before peer disconnection', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    events = []

    Async do |task|
      client.realtime.on_error { |context| events << [:error, context] }
      client.realtime.on_disconnect { |context| events << [:disconnect, context] }
      client.realtime.channel('contract').subscribe

      socket.invalid_frame
      task.with_timeout(0.2) { task.yield until events.length == 2 }
      client.realtime.disconnect
    end.wait

    expect(events.map(&:first)).to eq(%i[error disconnect])
    error_context = events.first.last
    expect(error_context).to be_a(Volcano::Realtime::ErrorContext)
    expect(error_context.code).to be_nil
    expect(error_context.message).to include('invalid realtime frame')
    expect(error_context.error).to be_a(Volcano::Realtime::ClosedError)
    expect(error_context).to be_frozen
    expect(error_context.error).to be_frozen
  end

  it 'prevents one error callback from mutating another callback context' do
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { raise IOError, 'socket open failed' }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    mutation_errors = []
    observed = []

    Async do |task|
      client.realtime.on_error do |context|
        begin
          context.error.message << 'mutated'
        rescue StandardError => e
          mutation_errors << e.class
        end
        begin
          context.error.backtrace << 'mutated'
        rescue StandardError => e
          mutation_errors << e.class
        end
      end
      client.realtime.on_error do |context|
        observed << [context.error.message, context.error.backtrace]
      end
      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Error::TransportError,
        'socket open failed'
      )
      task.with_timeout(0.2) { task.yield until observed.any? }
    end.wait

    expect(mutation_errors).to eq([FrozenError, FrozenError])
    expect(observed.first.first).to eq('socket open failed')
    expect(observed.first.last).not_to include('mutated')
  end

  it 'closes and reports an established connection when a socket write fails' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    events = []

    Async do |task|
      client.realtime.on_error { |context| events << [:error, context.message] }
      client.realtime.on_disconnect { |context| events << [:disconnect, context.reason] }
      socket.on_write = lambda do |command|
        raise IOError, 'socket write failed' if command.key?('subscribe')
      end

      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ClosedError,
        'socket write failed'
      )
      task.with_timeout(0.2) { task.yield until events.length == 2 }
      client.realtime.disconnect
    end.wait

    expect(events).to eq(
      [[:error, 'socket write failed'], [:disconnect, 'socket write failed']]
    )
    expect(client.realtime).not_to be_connected
    expect(socket).to be_closed
  end

  it 'keeps the connection open when a publication cannot be serialized' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    events = []

    Async do
      client.realtime.on_error { |context| events << context }
      channel = client.realtime.channel('contract')
      channel.subscribe

      expect { channel.send(event: 'message', value: Float::NAN) }.to raise_error(
        JSON::GeneratorError
      )
      expect(channel.send(event: 'message', value: 'valid')).to be_nil
      client.realtime.disconnect
    end.wait

    expect(events).to be_empty
    expect(socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe publish]
    )
  end

  it 'freezes string error codes before delivering shared contexts' do
    socket = SpecSupport::FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.reject(command.fetch('id'), 'permission denied', code: 'permission')
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    mutation_errors = []
    observed = []

    Async do |task|
      client.realtime.on_error do |context|
        [context.code, context.error.code].each do |code|
          code << '-mutated'
        rescue StandardError => e
          mutation_errors << e.class
        end
      end
      client.realtime.on_error { |context| observed << context.code }

      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ServerError
      )
      task.with_timeout(0.2) { task.yield until observed.any? }
    end.wait

    expect(mutation_errors).to eq([FrozenError, FrozenError])
    expect(observed).to eq(['permission'])
  end

  it 'finishes transport shutdown before an error callback disconnects again' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    disconnected = []

    Async do |task|
      client.realtime.on_error { client.realtime.disconnect }
      client.realtime.on_disconnect { |context| disconnected << context }
      client.realtime.channel('contract').subscribe

      socket.fail_read(IOError.new('socket read failed'))
      task.with_timeout(0.2) { task.yield until disconnected.any? }
    end.wait

    expect(disconnected.map(&:reason)).to eq(['socket read failed'])
    expect(socket).to be_closed
  end

  it 'does not report a connection after the protocol closes while handling its reply' do
    socket = SpecSupport::FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.connect_then_invalid(command.fetch('id'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    events = []

    Async do |task|
      client.realtime.on_connect { |context| events << [:connect, context] }
      client.realtime.on_disconnect { |context| events << [:disconnect, context] }
      client.realtime.on_error { |context| events << [:error, context] }

      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ClosedError,
        /invalid realtime frame/
      )
      task.with_timeout(0.2) { task.yield until events.any? }
    end.wait

    expect(events.map(&:first)).to eq([:error])
    expect(client.realtime).not_to be_connected
  end

  it 'reports a redacted error when opening the transport fails' do
    anon_key = 'anon key/fixture-secret'
    encoded_key = 'anon%20key%2Ffixture-secret'
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: anon_key,
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(address) { raise IOError, "failed to open #{address}" }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    errors = []

    Async do |task|
      client.realtime.on_error { |context| errors << context }
      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Error::TransportError
      )
      task.with_timeout(0.2) { task.yield until errors.any? }
    end.wait

    expect(errors.first.message).to include('apikey=[REDACTED]')
    expect(errors.first.message).not_to include(anon_key, encoded_key)
    expect(errors.first.error).to be_frozen
  end

  it 'reports one error when a pending connect receives a copied read failure' do
    socket = SpecSupport::FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.fail_read(IOError.new('socket read failed'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    errors = []

    Async do
      client.realtime.on_error { |context| errors << context }
      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ClosedError,
        'socket read failed'
      )
    end.wait

    expect(errors.length).to eq(1)
  end

  it 'preserves a connect rejection code in the error context' do
    socket = SpecSupport::FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.reject(command.fetch('id'), 'permission denied', code: 107)
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    errors = []

    Async do
      client.realtime.on_error { |context| errors << context }
      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ServerError
      )
    end.wait

    expect(errors.map(&:code)).to eq([107])
  end

  it 'runs connection callbacks outside protocol processing' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      started = Async::Queue.new
      release = Async::Queue.new
      client.realtime.on_connect do
        started.enqueue(true)
        release.dequeue
      end

      subscribing = task.async { client.realtime.channel('contract').subscribe }
      started.dequeue
      expect(task.with_timeout(0.2) { subscribing.wait }).to be_nil
      release.enqueue(true)
      client.realtime.disconnect
    end.wait
  end

  it 'reports connection state and removes one channel', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      channel = client.realtime.channel('contract')
      expect(client.realtime).not_to be_connected
      channel.subscribe
      expect(client.realtime).to be_connected

      expect(client.realtime.remove_channel('contract')).to be_nil

      expect(client.realtime.channel('contract')).not_to be(channel)
      expect(client.realtime).to be_connected
      expect(client.realtime.remove_channel('missing')).to be_nil
      client.realtime.disconnect
      expect(client.realtime).not_to be_connected
    end.wait

    expect(socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe unsubscribe]
    )
  end

  it 'removes all channels without disconnecting', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      first = client.realtime.channel('first')
      second = client.realtime.channel('second')
      first.subscribe
      second.subscribe

      expect(client.realtime.remove_all_channels).to be_nil

      expect(client.realtime.channel('first')).not_to be(first)
      expect(client.realtime.channel('second')).not_to be(second)
      expect(client.realtime).to be_connected
      client.realtime.disconnect
    end.wait

    expect(socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe subscribe unsubscribe unsubscribe]
    )
  end

  it 'detaches a removed channel before recreating it', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    old_messages = []
    new_messages = []

    Async do
      old_channel = client.realtime.channel('contract')
      old_channel.on('message') { |message| old_messages << message }
      old_channel.subscribe
      client.realtime.remove_channel('contract')

      new_channel = client.realtime.channel('contract')
      new_channel.on('message') { |message| new_messages << message }
      new_channel.subscribe
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 'new' }
      )
      Async::Task.current.yield until new_messages.any?
      client.realtime.disconnect
    end.wait

    expect(old_messages).to be_empty
    expect(new_messages).to eq([{ 'event' => 'message', 'value' => 'new' }])
  end

  it 'retains a channel when removal fails' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      channel = client.realtime.channel('contract')
      channel.subscribe
      socket.on_write = lambda do |command|
        next unless command.key?('unsubscribe')

        socket.reject(command.fetch('id'), 'unsubscribe failed')
        :defer
      end

      expect { client.realtime.remove_channel('contract') }.to raise_error(
        Volcano::Realtime::ServerError,
        'unsubscribe failed'
      )
      expect(client.realtime.channel('contract')).to be(channel)
      socket.on_write = nil
      client.realtime.remove_channel('contract')
      expect(client.realtime.channel('contract')).not_to be(channel)
      client.realtime.disconnect
    end.wait
  end

  it 'restores a channel after its unsubscribe request is rejected' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.subscribe
      first_socket.on_write = lambda do |command|
        next unless command.key?('unsubscribe')

        first_socket.reject(command.fetch('id'), 'unsubscribe failed')
        :defer
      end

      expect { channel.unsubscribe }.to raise_error(
        Volcano::Realtime::ServerError,
        'unsubscribe failed'
      )
      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    expect(restored_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
  end

  it 'restores a channel when its unsubscribe request loses the transport' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    unsubscribe_started = Async::Queue.new
    lose_transport = Async::Queue.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.subscribe
      first_socket.on_write = lambda do |command|
        next unless command.key?('unsubscribe')

        unsubscribe_started.enqueue(true)
        lose_transport.dequeue
        first_socket.fail_read(IOError.new('socket failed'))
        :defer
      end

      unsubscribing = task.async do
        channel.unsubscribe
      rescue StandardError => e
        e
      end
      unsubscribe_started.dequeue
      expect(channel).to be_subscription_desired
      lose_transport.enqueue(true)
      expect(unsubscribing.wait).to be_a(Volcano::Realtime::ClosedError)
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    expect(restored_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
  end

  it 'reports a peer-closed transport as disconnected' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      channel = client.realtime.channel('contract')
      channel.subscribe
      expect(client.realtime).to be_connected

      socket.close
      Async::Task.current.yield while client.realtime.connected?

      expect(client.realtime).not_to be_connected
      expect(client.realtime.remove_channel('contract')).to be_nil
      expect(client.realtime.channel('contract')).not_to be(channel)
    end.wait
  end

  it 'reconnects and restores subscribed channels after transport loss' do
    first_socket = SpecSupport::FacadeSocket.new
    second_socket = SpecSupport::FacadeSocket.new
    third_socket = SpecSupport::FacadeSocket.new
    sockets = [first_socket, second_socket, third_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = []

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received << message }
      channel.subscribe

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until second_socket.commands.any? { |command| command.key?('subscribe') }
      end
      second_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 'restored' }
      )
      task.with_timeout(0.2) { task.yield until received.any? }

      second_socket.fail_read(IOError.new('socket failed again'))
      task.with_timeout(0.2) do
        task.yield until third_socket.commands.any? { |command| command.key?('subscribe') }
      end
      third_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 'restored-again' }
      )
      task.with_timeout(0.2) { task.yield until received.length == 2 }
      client.realtime.disconnect
    end.wait

    expect(first_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
    expect(second_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
    expect(third_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
    expect(received).to eq(
      [
        { 'event' => 'message', 'value' => 'restored' },
        { 'event' => 'message', 'value' => 'restored-again' }
      ]
    )
    expect(sockets).to be_empty
  end

  it 'does not restore a channel unsubscribed during an outage' do
    first_socket = SpecSupport::FacadeSocket.new
    second_socket = SpecSupport::FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    sockets = [first_socket, second_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: lambda do |_attempt|
        reconnect_waiting.enqueue(true)
        allow_reconnect.dequeue
        0
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      channel = client.realtime.channel('contract')
      retained = client.realtime.channel('retained')
      channel.subscribe
      retained.subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      reconnect_waiting.dequeue

      channel.unsubscribe
      allow_reconnect.enqueue(true)
      task.with_timeout(0.2) do
        task.yield until second_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    expect(second_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
    expect(second_socket.commands.last.dig('subscribe', 'channel')).to eq('broadcast:retained')
  end

  it 'retries a failed reconnect with increasing backoff attempts' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    attempts = []
    opened = 0
    factory = lambda do |_address|
      opened += 1
      next first_socket if opened == 1
      raise IOError, 'reconnect failed' if opened == 2

      restored_socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory,
      _realtime_reconnect_delay: lambda do |attempt|
        attempts << attempt
        0
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      client.realtime.channel('contract').subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    expect(attempts).to eq([0, 1])
    expect(opened).to eq(3)
  end

  it 'retries when the replacement transport fails during restoration' do
    first_socket = SpecSupport::FacadeSocket.new
    failed_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    failed_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      failed_socket.fail_read(IOError.new('restore failed'))
      :defer
    end
    sockets = [first_socket, failed_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      client.realtime.channel('contract').subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    expect(failed_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
    expect(restored_socket.commands.map { |command| command.keys.fetch(1) }).to eq(
      %w[connect subscribe]
    )
  end

  it 'allows channel creation while another channel is being restored' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    restore_started = Async::Queue.new
    allow_restore = Async::Queue.new
    restored_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      restore_started.enqueue(true)
      allow_restore.dequeue
      nil
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      client.realtime.channel('contract').subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      restore_started.dequeue
      created = task.async do
        client.realtime.channel('new')
      rescue StandardError => e
        e
      end
      allow_restore.enqueue(true)

      expect(task.with_timeout(0.2) { created.wait }).to be_a(Volcano::Realtime::Channel)
      client.realtime.disconnect
    end.wait
  end

  it 'restores old channels when a foreground subscription reconnects first' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: lambda do |_attempt|
        reconnect_waiting.enqueue(true)
        allow_reconnect.dequeue
        0
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      client.realtime.channel('old').subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      reconnect_waiting.dequeue
      client.realtime.channel('new').subscribe
      allow_reconnect.enqueue(true)
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? do |command|
          command.dig('subscribe', 'channel') == 'broadcast:old'
        end
      end
      client.realtime.disconnect
    end.wait

    subscribed_channels = restored_socket.commands.filter_map do |command|
      command.dig('subscribe', 'channel')
    end
    expect(subscribed_channels).to contain_exactly('broadcast:new', 'broadcast:old')
  end

  it 'preserves subscription intent when transport loss follows the reply' do
    failed_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    failed_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      reply = JSON.generate('id' => command.fetch('id'), 'result' => {})
      failed_socket.receive_raw("#{reply}\n{")
      :defer
    end
    sockets = [failed_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      expect { client.realtime.channel('contract').subscribe }.to raise_error(
        Volcano::Realtime::ClosedError,
        /invalid realtime frame/
      )
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait
  end

  it 'retries a transient channel rejection on the live replacement transport' do
    first_socket = SpecSupport::FacadeSocket.new
    restored_socket = SpecSupport::FacadeSocket.new
    rejected = false
    restored_socket.on_write = lambda do |command|
      next unless command.key?('subscribe') && !rejected

      rejected = true
      restored_socket.reject(command.fetch('id'), 'temporarily unavailable')
      :defer
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      client.realtime.channel('contract').subscribe
      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.count do |command|
          command.key?('subscribe')
        end == 2
      end
      client.realtime.disconnect
    end.wait

    expect(restored_socket.commands.count { |command| command.key?('connect') }).to eq(1)
  end

  it 'keeps channel teardown private' do
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { SpecSupport::FacadeSocket.new }
    )

    expect { client.realtime.channel('contract').remove }.to raise_error(NoMethodError)
  end

  it 'removes an inactive channel without connecting', :aggregate_failures do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )

    Async do
      channel = client.realtime.channel('contract')

      expect(client.realtime.remove_channel('contract')).to be_nil

      expect(client.realtime.channel('contract')).not_to be(channel)
      expect(client.realtime).not_to be_connected
    end.wait

    expect(socket.commands).to be_empty
  end

  it 'continues removing channels after one removal fails' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      first = client.realtime.channel('first')
      second = client.realtime.channel('second')
      first.subscribe
      second.subscribe
      socket.on_write = lambda do |command|
        next unless command.dig('unsubscribe', 'channel') == 'broadcast:first'

        socket.reject(command.fetch('id'), 'unsubscribe failed')
        :defer
      end

      expect { client.realtime.remove_all_channels }.to raise_error(
        Volcano::Realtime::ServerError,
        'unsubscribe failed'
      )
      expect(client.realtime.channel('first')).to be(first)
      expect(client.realtime.channel('second')).not_to be(second)
      socket.on_write = nil
      client.realtime.disconnect
    end.wait
  end

  it 'waits for removal before looking up the same channel' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      old_channel = client.realtime.channel('contract')
      old_channel.subscribe
      socket.on_write = lambda do |command|
        next unless command.key?('unsubscribe')

        entered.enqueue(true)
        release.dequeue
      end
      removing = task.async { client.realtime.remove_channel('contract') }
      entered.dequeue
      lookup_finished = false
      lookup = task.async do
        client.realtime.channel('contract').tap { lookup_finished = true }
      end
      task.yield

      expect(lookup_finished).to be(false)
      release.enqueue(true)
      removing.wait
      expect(lookup.wait).not_to be(old_channel)
      client.realtime.disconnect
    end.wait
  end

  it 'preserves the API base path in the realtime endpoint' do
    socket = SpecSupport::FacadeSocket.new
    addresses = []
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev/volcano/',
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: lambda do |address|
        addresses << address
        socket
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      client.realtime.channel('contract').subscribe
      client.realtime.disconnect
    end.wait

    expect(addresses).to eq(
      ['wss://api.test.volcano.dev/volcano/realtime/v1/websocket?apikey=anon-key']
    )
  end

  it 'rejects duplicate subscriptions' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do
      channel = client.realtime.channel('contract')
      channel.subscribe
      expect { channel.subscribe }.to raise_error(Volcano::Realtime::DuplicateSubscriptionError)
      client.realtime.disconnect
    end.wait
  end

  it 'does not expose a protocol before its connect response completes' do
    socket = SpecSupport::FacadeSocket.new
    connect_written = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      connect_written.enqueue(command.fetch('id'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      connecting = task.async { client.realtime.send(:protocol) }
      connect_id = connect_written.dequeue
      subscribe_finished = false
      subscribing = task.async do
        client.realtime.channel('contract').subscribe
        subscribe_finished = true
      end
      task.yield
      finished_before_connect = subscribe_finished
      commands_before_connect = socket.commands.map { |command| command.keys.fetch(1) }
      socket.respond(connect_id)

      task.with_timeout(0.2) { connecting.wait }
      task.with_timeout(0.2) { subscribing.wait }
      expect(finished_before_connect).to be(false)
      expect(commands_before_connect).to eq(%w[connect])
      client.realtime.disconnect
    end.wait
  end

  it 'serializes concurrent subscriptions on one channel' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    blocked = false
    socket.on_write = lambda do |command|
      next unless command.key?('subscribe') && !blocked

      blocked = true
      entered.enqueue(true)
      release.dequeue
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      channel = client.realtime.channel('contract')
      first = task.async { channel.subscribe }
      entered.dequeue
      second = task.async do
        channel.subscribe
      rescue StandardError => e
        e
      end
      task.yield
      release.enqueue(true)

      expect(task.with_timeout(0.2) { first.wait }).to be_nil
      expect(task.with_timeout(0.2) { second.wait }).to be_a(
        Volcano::Realtime::DuplicateSubscriptionError
      )
      expect(socket.commands.count { |command| command.key?('subscribe') }).to eq(1)
      client.realtime.disconnect
    end.wait
  end

  it 'waits for an in-flight subscription before unsubscribing' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      entered.enqueue(true)
      release.dequeue
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      channel = client.realtime.channel('contract')
      subscribing = task.async { channel.subscribe }
      entered.dequeue
      unsubscribe_finished = false
      unsubscribing = task.async do
        channel.unsubscribe
        unsubscribe_finished = true
      end
      task.yield
      finished_before_subscribe = unsubscribe_finished
      release.enqueue(true)

      task.with_timeout(0.2) { subscribing.wait }
      task.with_timeout(0.2) { unsubscribing.wait }
      expect(finished_before_subscribe).to be(false)
      expect(socket.commands.map { |command| command.keys.fetch(1) }).to eq(
        %w[connect subscribe unsubscribe]
      )
      expect { channel.send(event: 'message') }.to raise_error(
        Volcano::Realtime::ClosedError,
        'realtime channel is not subscribed'
      )
      client.realtime.disconnect
    end.wait
  end

  it 'routes an overlapping project-prefixed publication only to the longest channel' do
    socket = SpecSupport::FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    short_received = []
    long_received = []

    Async do |task|
      short_channel = client.realtime.channel('foo')
      long_channel = client.realtime.channel('x:broadcast:foo')
      short_channel.on('message') { |message| short_received << message }
      long_channel.on('message') { |message| long_received << message }
      short_channel.subscribe
      long_channel.subscribe
      socket.publication(
        channel: 'project-id:broadcast:x:broadcast:foo',
        data: { 'event' => 'message', 'value' => 'long' }
      )
      task.with_timeout(0.2) { task.yield until long_received.any? }

      expect(short_received).to be_empty
      expect(long_received).to eq([{ 'event' => 'message', 'value' => 'long' }])
      client.realtime.disconnect
    end.wait
  end

  it 'redacts the anonymous key from connection exceptions' do
    anon_key = 'anon key/fixture-secret'
    encoded_key = 'anon%20key%2Ffixture-secret'
    factory = lambda do |address|
      raise IOError, "connection failed for #{address}"
    end
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: anon_key,
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect do
      client.realtime.channel('contract').subscribe
    end.to raise_error(Volcano::Error::TransportError) { |error|
      expect(error.message).to include('connection failed for')
      expect(error.message).to include('apikey=[REDACTED]')
      expect(error.message).not_to include(anon_key, encoded_key)
    }
  end

  it 'opens one socket when the protocol is first used concurrently' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    opened = 0
    factory = lambda do |_address|
      opened += 1
      entered.enqueue(true)
      release.dequeue
      socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      first = task.async { client.realtime.send(:protocol) }
      entered.dequeue
      second = task.async { client.realtime.send(:protocol) }
      task.yield
      release.enqueue(true)

      expect(task.with_timeout(0.2) { first.wait }).to equal(
        task.with_timeout(0.2) { second.wait }
      )
      expect(opened).to eq(1)
      client.realtime.disconnect
    end.wait
  end

  it 'aborts an opening socket when the authenticated session changes' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    factory = lambda do |_address|
      entered.enqueue(true)
      release.dequeue
      socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      opening = task.async do
        client.realtime.channel('contract').subscribe
      rescue StandardError => e
        e
      end
      entered.dequeue
      client.store_session(
        Volcano::Session.new(
          access_token: 'other-access', refresh_token: 'other-refresh', user_id: 'other-user'
        )
      )
      release.enqueue(true)

      expect(task.with_timeout(0.2) { opening.wait }).to be_a(
        Volcano::Error::SessionChangedError
      )
      expect(socket.commands).to be_empty
      expect(socket).to be_closed
    end.wait
  end

  it 'waits for an opening protocol before disconnecting it' do
    socket = SpecSupport::FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    factory = lambda do |_address|
      entered.enqueue(true)
      release.dequeue
      socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: factory
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    Async do |task|
      opening = task.async { client.realtime.send(:protocol) }
      entered.dequeue
      closing = task.async { client.realtime.disconnect }
      task.yield
      release.enqueue(true)

      task.with_timeout(0.2) { opening.wait }
      task.with_timeout(0.2) { closing.wait }
      expect(socket).to be_closed
    end.wait
  end
end
