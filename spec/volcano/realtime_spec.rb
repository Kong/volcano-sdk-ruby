# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'

RSpec.describe Volcano::Realtime do
  RealtimeResponse = Data.define(:status, :body, :headers, :data) unless const_defined?(:RealtimeResponse)

  unless const_defined?(:DelayedProducerObservation)
    DelayedProducerObservation = Data.define(
      :channel, :recovery_offset, :live_offset, :producer_waiting,
      :live_queued, :rejection_started, :rejection_completed
    ) do
      def recovery?(delivery)
        delivery.channel == channel && delivery.recovered &&
          delivery.publication['offset'] == recovery_offset
      end

      def live?(delivery)
        delivery.channel == channel && !delivery.recovered &&
          delivery.publication['offset'] == live_offset
      end

      def signal_for(delivery)
        return producer_waiting if recovery?(delivery)

        rejection_started if live?(delivery)
      end
    end
  end

  class RealtimeAuthTransport
    def auth_signin(**)
      RealtimeResponse.new(
        status: 200,
        body: {
          'access_token' => 'access-token',
          'refresh_token' => 'refresh-token',
          'user' => { 'id' => 'user-123' }
        },
        headers: {},
        data: nil
      )
    end
  end

  class RealtimeDatabaseTransport < RealtimeAuthTransport
    attr_reader :queries, :query_threads

    def initialize(rows = [{ 'id' => 42, 'body' => 'fetched' }], error: nil)
      @rows = rows
      @error = error
      @queries = []
      @query_threads = []
    end

    def query_database_select(**arguments)
      @queries << arguments
      @query_threads << Thread.current
      raise @error if @error

      RealtimeResponse.new(
        status: 200,
        body: { 'data' => @rows },
        headers: {},
        data: nil
      )
    end
  end

  class BlockingRealtimeDatabaseTransport < RealtimeDatabaseTransport
    attr_reader :started, :release

    def initialize
      super
      @started = ThreadSignalQueue.new
      @release = ThreadSignalQueue.new
    end

    def query_database_select(**arguments)
      @started.enqueue(true)
      @release.dequeue
      super
    end
  end

  class FirstBlockingRealtimeDatabaseTransport < RealtimeDatabaseTransport
    attr_reader :release, :started

    def initialize
      super
      @blocked = false
      @started = ThreadSignalQueue.new
      @release = ThreadSignalQueue.new
    end

    def query_database_select(**arguments)
      unless @blocked
        @blocked = true
        @started.enqueue(true)
        @release.dequeue
      end
      super
    end
  end

  class ThreadSignalQueue < Queue
    alias dequeue pop
    alias enqueue push
  end

  class FacadeSocket
    attr_accessor :on_write
    attr_reader :commands

    def initialize
      @incoming = Async::Queue.new
      @commands = []
      @closed = false
    end

    def write(frame)
      command = JSON.parse(frame.to_str)
      @commands << command
      return if on_write&.call(command) == :defer

      result = command.key?('connect') ? { 'client' => 'client-123' } : {}
      respond(command.fetch('id'), result: result)
    end

    def read
      value = @incoming.dequeue
      raise value if value.is_a?(Exception)

      value
    end

    def publication(channel:, data:, epoch: nil, offset: nil)
      publication = { 'data' => data }
      publication['epoch'] = epoch if epoch
      publication['offset'] = offset if offset
      @incoming.enqueue(
        JSON.generate(
          'push' => {
            'channel' => channel,
            'pub' => publication
          }
        )
      )
    end

    def presence_event(channel:, event:, info:)
      @incoming.enqueue(
        JSON.generate(
          'push' => {
            'channel' => channel,
            event => { 'info' => info }
          }
        )
      )
    end

    def respond(id, result: {})
      @incoming.enqueue(JSON.generate('id' => id, 'result' => result))
    end

    def receive_raw(frame)
      @incoming.enqueue(frame)
    end

    def reject(id, message, code: nil)
      error = { 'message' => message }
      error['code'] = code if code
      @incoming.enqueue(JSON.generate('id' => id, 'error' => error))
    end

    def invalid_frame
      @incoming.enqueue('{')
    end

    def fail_read(error)
      @incoming.enqueue(error)
    end

    def connect_then_invalid(id)
      reply = JSON.generate('id' => id, 'result' => { 'client' => 'client-123' })
      @incoming.enqueue("#{reply}\n{")
    end

    def close
      return if @closed

      @closed = true
      @incoming.enqueue(nil)
    end

    def closed?
      @closed
    end
  end

  class DelayedRejectionResponder
    attr_reader :reader_passed_queue_fill

    def initialize(socket, replacement: nil)
      @socket = socket
      @replacement = replacement
      @target_subscriptions = 0
      @reader_passed_queue_fill = Async::Queue.new
    end

    def call(command)
      return respond_to_subscription(command) if command.key?('subscribe')
      return respond_to_unsubscribe(command) if command.key?('unsubscribe')

      acknowledge_queue_fill if command.empty?
    end

    private

    def respond_to_subscription(command)
      channel = command.dig('subscribe', 'channel')
      @socket.respond(command.fetch('id'), result: subscription_result(channel))
      :defer
    end

    def respond_to_unsubscribe(command)
      @socket.respond(command.fetch('id'))
      :defer
    end

    def acknowledge_queue_fill
      @reader_passed_queue_fill.enqueue(true)
      :defer
    end

    def subscription_result(channel)
      return blocker_result if channel == 'broadcast:blocker'

      @target_subscriptions += 1
      return initial_target_result if @target_subscriptions == 1 || !@replacement

      @replacement
    end

    def blocker_result = { 'epoch' => 'blocker-epoch', 'offset' => 0, 'publications' => [] }

    def initial_target_result
      {
        'epoch' => 'epoch-1', 'offset' => 2,
        'publications' => [
          { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } }
        ]
      }
    end
  end

  def realtime_client(socket, transport: RealtimeAuthTransport.new)
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: transport,
      _realtime_socket_factory: ->(_address) { socket }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    client
  end

  def reconnecting_realtime_client(sockets)
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    client
  end

  def delayed_rejection_socket(replacement: nil)
    socket = FacadeSocket.new
    responder = DelayedRejectionResponder.new(socket, replacement:)
    socket.on_write = responder
    [socket, responder.reader_passed_queue_fill]
  end

  def reconnecting_delayed_rejection_client(replacement:)
    socket, reader_passed_queue_fill = delayed_rejection_socket(replacement:)
    restored_socket = FacadeSocket.new
    client = reconnecting_realtime_client([socket, restored_socket])
    [socket, restored_socket, reader_passed_queue_fill, client]
  end

  def expect_reconnect_position(socket, epoch:, offset:)
    subscribe = socket.commands.find do |command|
      command.dig('subscribe', 'channel') == 'broadcast:contract'
    end
    expect(subscribe.fetch('subscribe')).to include('epoch' => epoch, 'offset' => offset)
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

  def observe_blocked_lifecycle_acquisition(channel, waiting:, resumed:)
    lock = channel.instance_variable_get(:@lifecycle_lock)
    lock.singleton_class.prepend(blocked_lifecycle_observer(waiting:, resumed:))
  end

  def blocked_lifecycle_observer(waiting:, resumed:)
    Module.new do
      define_method(:wait) do
        return super() unless blocking?

        waiting.enqueue(true)
        super()
        resumed.enqueue(true)
      end
      private :wait
    end
  end

  def observe_broadcast_admission(channel, offset:, completed:)
    observer = Module.new do
      define_method(:complete_broadcast_publication) do |context|
        observed = context.publication['offset'] == offset
        super(context)
      ensure
        completed.enqueue(true) if observed
      end
      private :complete_broadcast_publication
    end
    channel.singleton_class.prepend(observer)
  end

  def observe_broadcast_delivery(channel, offset:, completed:)
    observer = Module.new do
      define_method(:deliver_broadcast) do |event, data, context|
        observed = context.publication['offset'] == offset
        super(event, data, context)
      ensure
        completed.enqueue(true) if observed
      end
      private :deliver_broadcast
    end
    channel.singleton_class.prepend(observer)
  end

  def observe_publication_drop(protocol, offset:, completed:)
    observer = Module.new do
      define_method(:drop_publication) do |channel, publication|
        observed = publication.is_a?(Hash) && publication['offset'] == offset
        super(channel, publication)
      ensure
        completed.enqueue(true) if observed
      end
    end
    protocol.singleton_class.prepend(observer)
  end

  def observe_publication_drops(protocol, channel:, drops:)
    observer = Module.new do
      define_method(:drop_publication) do |name, publication|
        drops << publication['offset'] if name == channel && publication.is_a?(Hash)
        super(name, publication)
      end
    end
    protocol.singleton_class.prepend(observer)
  end

  def observe_recovered_queue_saturation(protocol, channel:, observed:)
    observer = Module.new do
      define_method(:publication_batch_enqueued?) do |name, deliveries|
        if name == channel && deliveries.first.recovered && @ordered_publication_queue.limited?
          observed.enqueue(
            reader: Async::Task.current.equal?(@reader_task),
            queue_sizes: [@callback_queue.size, @ordered_publication_queue.size],
            ordered_count: @ordered_publication_counts[name]
          )
        end
        super(name, deliveries)
      end
      private :publication_batch_enqueued?
    end
    protocol.singleton_class.prepend(observer)
  end

  def observe_immediate_reader_rejection(protocol, **options)
    protocol.singleton_class.prepend(immediate_reader_rejection_observer(**options))
  end

  def immediate_reader_rejection_observer(started:, completed:)
    Module.new do
      define_method(:reject_publication) do |delivery|
        started.enqueue(
          [delivery.channel, delivery.publication['offset'],
           Async::Task.current.equal?(@reader_task), @callback_queue.limited?,
           @ordered_publication_counts[delivery.channel]]
        )
        super(delivery)
      ensure
        completed.enqueue(true)
      end
      private :reject_publication
    end
  end

  def observe_delayed_producer_rejection(protocol, observation)
    protocol.singleton_class.prepend(delayed_live_enqueue_observer(observation))
    protocol.singleton_class.prepend(delayed_admission_observer(observation))
  end

  def delayed_live_enqueue_observer(observation)
    Module.new do
      define_method(:enqueue_ordered_publication) do |delivery|
        observed = observation.live?(delivery)
        super(delivery)
      ensure
        observation.live_queued.enqueue(@ordered_publication_counts[observation.channel]) if observed
      end
      private :enqueue_ordered_publication
    end
  end

  def delayed_admission_observer(observation)
    Module.new do
      define_method(:admit_publication) do |delivery, enforce_limit:|
        signal = observation.signal_for(delivery)
        signal&.enqueue([Async::Task.current.equal?(@publication_producer_task),
                         enforce_limit, @callback_queue.limited?])
        super(delivery, enforce_limit:)
      ensure
        observation.rejection_completed.enqueue(true) if observation.live?(delivery)
      end
      private :admit_publication
    end
  end

  it 'exposes the canonical channel name' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)

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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new(
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
    socket = FacadeSocket.new
    rows = Array.new(51) { |index| { 'id' => index + 1 } }
    transport = RealtimeDatabaseTransport.new(rows)
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
    socket = FacadeSocket.new
    rows = Array.new(3) { |index| { 'id' => index + 1 } }
    transport = RealtimeDatabaseTransport.new(rows)
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
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)
    channel = client.realtime.channel('public:messages', type: :postgres)

    expect do
      client.realtime.channel('public:messages', type: :postgres, auto_fetch: false)
    end.to raise_error(ArgumentError, 'conflicting auto_fetch option for postgres:public:messages')
    expect(client.realtime.channel('public:messages', type: :postgres)).to equal(channel)
  end

  it 'delivers Postgres changes to an unfiltered on callback' do
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
    error = Volcano::Error::TransportError.new('database unavailable')
    transport = RealtimeDatabaseTransport.new(error: error)
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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

  it 'preserves a queued change when the same user refreshes their token' do
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = FirstBlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
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
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)

    expect { client.realtime.database_name = 'Not Valid' }.to raise_error(
      ArgumentError, 'database name must match ^[a-z0-9_]+$ and contain at most 64 characters'
    )
  end

  it 'does not deliver queued changes after the authenticated user changes' do
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = BlockingRealtimeDatabaseTransport.new
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
    socket = FacadeSocket.new
    transport = RealtimeDatabaseTransport.new
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
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)
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

  it 'tracks an immutable presence snapshot through sync, join, leave, and unsubscribe', :aggregate_failures do
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
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
    socket = FacadeSocket.new
    addresses = []
    factory = lambda do |address|
      addresses << address
      socket
    end
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: 'anon key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.reject(command.fetch('id'), 'permission denied', code: 'permission')
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.connect_then_invalid(command.fetch('id'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.fail_read(IOError.new('socket read failed'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      socket.reject(command.fetch('id'), 'permission denied', code: 107)
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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

  it 'clears protocol recovery state only when a broadcast channel is removed' do
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 0 })
      :defer
    end
    client = realtime_client(socket)

    Async do
      channel = client.realtime.channel('contract')
      channel.subscribe
      protocol = client.realtime.send(:protocol)
      protocol.drop_publication(
        'broadcast:contract', 'epoch' => 'epoch-1', 'offset' => 1
      )

      channel.unsubscribe
      expect(protocol.position('broadcast:contract')).to eq(epoch: 'epoch-1', offset: 0)
      expect(protocol.instance_variable_get(:@position_gaps)).to include('broadcast:contract')

      client.realtime.remove_channel('contract')
      expect(protocol.position('broadcast:contract')).to be_nil
      expect(protocol.instance_variable_get(:@position_gaps)).not_to include('broadcast:contract')
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'removes all channels without disconnecting', :aggregate_failures do
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    unsubscribe_started = Async::Queue.new
    lose_transport = Async::Queue.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    second_socket = FacadeSocket.new
    third_socket = FacadeSocket.new
    sockets = [first_socket, second_socket, third_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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

  it 'recovers a broadcast from its last delivered position' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 1 })
      :defer
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message) }
      channel.subscribe
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 'live' },
        epoch: 'epoch-1',
        offset: 2
      )
      task.with_timeout(0.2) { received.dequeue }

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to include(
      'channel' => 'broadcast:contract',
      'recover' => true,
      'epoch' => 'epoch-1',
      'offset' => 2
    )
  end

  it 'does not recover past a malformed broadcast publication' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 0 })
      :defer
    end
    client = reconnecting_realtime_client([first_socket, restored_socket])
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      channel.subscribe
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: 'malformed', epoch: 'epoch-1', offset: 1
      )
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 }, epoch: 'epoch-1', offset: 2
      )
      expect(task.with_timeout(0.2) { received.dequeue }).to eq(2)

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    ensure
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to include(
      'epoch' => 'epoch-1', 'offset' => 0
    )
  end

  it 'does not recover past a broadcast received without a message listener' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 0 })
      :defer
    end
    client = reconnecting_realtime_client([first_socket, restored_socket])
    dropped = Async::Queue.new
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.subscribe
      protocol = client.realtime.send(:protocol)
      observe_publication_drop(protocol, offset: 1, completed: dropped)
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 1 }, epoch: 'epoch-1', offset: 1
      )
      task.with_timeout(0.2) { dropped.dequeue }

      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 }, epoch: 'epoch-1', offset: 2
      )
      expect(task.with_timeout(0.2) { received.dequeue }).to eq(2)

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    ensure
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to include(
      'epoch' => 'epoch-1', 'offset' => 0
    )
  end

  it 'does not recover past an unsupported broadcast event' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 0 })
      :defer
    end
    client = reconnecting_realtime_client([first_socket, restored_socket])
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      channel.subscribe
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'unsupported', 'value' => 1 }, epoch: 'epoch-1', offset: 1
      )
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 }, epoch: 'epoch-1', offset: 2
      )
      expect(task.with_timeout(0.2) { received.dequeue }).to eq(2)

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    ensure
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to include(
      'epoch' => 'epoch-1', 'offset' => 0
    )
  end

  it 'subscription expires before callback dispatch' do
    socket = FacadeSocket.new
    unsubscribe_started = Async::Queue.new
    allow_unsubscribe = Async::Queue.new
    admission_waiting = Async::Queue.new
    admission_resumed = Async::Queue.new
    socket.on_write = lambda do |command|
      if command.key?('subscribe')
        socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 1 })
      elsif command.key?('unsubscribe')
        unsubscribe_started.enqueue(true)
        allow_unsubscribe.dequeue
        socket.respond(command.fetch('id'))
      else
        next
      end
      :defer
    end
    client = realtime_client(socket)
    received = []
    drops = []

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received << message.fetch('value') }
      channel.subscribe
      admission_completed = Async::Queue.new
      observe_broadcast_admission(channel, offset: 2, completed: admission_completed)
      protocol = client.realtime.send(:protocol)
      drop_observer = Module.new do
        define_method(:drop_publication) do |name, publication|
          drops << publication.fetch('offset') if name == 'broadcast:contract'
          super(name, publication)
        end
      end
      protocol.singleton_class.prepend(drop_observer)
      observe_blocked_lifecycle_acquisition(
        channel,
        waiting: admission_waiting,
        resumed: admission_resumed
      )

      unsubscribing = nil
      allowed = false
      begin
        unsubscribing = task.async { channel.unsubscribe }
        task.with_timeout(0.2) { unsubscribe_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 2 },
          epoch: 'epoch-1',
          offset: 2
        )
        task.with_timeout(0.2) { admission_waiting.dequeue }
        allow_unsubscribe.enqueue(true)
        allowed = true
        task.with_timeout(0.2) { unsubscribing.wait }
        task.with_timeout(0.2) { admission_resumed.dequeue }
        task.with_timeout(0.2) { admission_completed.dequeue }
      ensure
        allow_unsubscribe.enqueue(true) unless allowed
        unsubscribing.stop if unsubscribing&.running?
        client.realtime.disconnect
      end
    end.wait

    expect(received).to be_empty
    expect(drops).to be_empty
  end

  it 'does not duplicate a queued broadcast after explicit resubscribe' do
    socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    restored_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      publications = if command.dig('subscribe', 'offset') == 2
                       [{ 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }]
                     else
                       []
                     end
      restored_socket.respond(
        command.fetch('id'),
        result: { 'epoch' => 'epoch-1', 'offset' => 3, 'publications' => publications }
      )
      :defer
    end
    subscribe_count = 0
    reader_passed_offset_three = Async::Queue.new
    socket.on_write = lambda do |command|
      if command.key?('subscribe')
        subscribe_count += 1
        result = if subscribe_count == 1
                   { 'epoch' => 'epoch-1', 'offset' => 1 }
                 else
                   {
                     'epoch' => 'epoch-1',
                     'offset' => 3,
                     'publications' => [
                       { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }
                     ]
                   }
                 end
        socket.respond(command.fetch('id'), result: result)
      elsif command.empty?
        reader_passed_offset_three.enqueue(true)
      else
        socket.respond(command.fetch('id')) unless command.key?('connect')
        next if command.key?('connect')
      end
      :defer
    end
    client = reconnecting_realtime_client([socket, restored_socket])
    offset_two_started, release_offset_two, offset_three_admitted, restored_live =
      Array.new(4) { Async::Queue.new }
    results = { received: [] }

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') do |message|
        value = message.fetch('value')
        results.fetch(:received) << value
        restored_live.enqueue(true) if value == 4
        next unless value == 2

        offset_two_started.enqueue(true)
        release_offset_two.dequeue
      end
      channel.subscribe
      observe_broadcast_admission(channel, offset: 3, completed: offset_three_admitted)
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 },
        epoch: 'epoch-1',
        offset: 2
      )
      task.with_timeout(0.2) { offset_two_started.dequeue }
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 3 },
        epoch: 'epoch-1',
        offset: 3
      )
      socket.receive_raw('{}')
      released = false
      begin
        task.with_timeout(0.2) { reader_passed_offset_three.dequeue }
        channel.unsubscribe
        channel.subscribe
        release_offset_two.enqueue(true)
        released = true
        task.with_timeout(0.2) { 2.times { offset_three_admitted.dequeue } }
        results[:position] = client.realtime.send(:protocol).position('broadcast:contract')

        socket.fail_read(IOError.new('socket failed'))
        task.with_timeout(0.2) do
          task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
        end
        restored_socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 4 },
          epoch: 'epoch-1',
          offset: 4
        )
        task.with_timeout(0.2) { restored_live.dequeue }
      ensure
        release_offset_two.enqueue(true) unless released
        client.realtime.disconnect
      end
    end.wait

    expect(results.fetch(:received)).to eq([2, 3, 4])
    expect(results.fetch(:position)).to eq(epoch: 'epoch-1', offset: 3)
    restored_subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(restored_subscribe.fetch('subscribe')).to include('epoch' => 'epoch-1', 'offset' => 3)
  end

  it 'does not let queued work mutate a permanently recreated channel' do
    socket = FacadeSocket.new
    subscribe_count = 0
    reader_passed_offset_three = Async::Queue.new
    socket.on_write = lambda do |command|
      if command.key?('subscribe')
        subscribe_count += 1
        result = if subscribe_count == 1
                   { 'epoch' => 'epoch-1', 'offset' => 1, 'publications' => [] }
                 else
                   { 'epoch' => 'epoch-2', 'offset' => 10, 'publications' => [] }
                 end
        socket.respond(command.fetch('id'), result: result)
      elsif command.empty?
        reader_passed_offset_three.enqueue(true)
      else
        socket.respond(command.fetch('id')) unless command.key?('connect')
        next if command.key?('connect')
      end
      :defer
    end
    client = realtime_client(socket)
    offset_two_started = Async::Queue.new
    release_offset_two = Async::Queue.new
    old_offset_three_processed = Async::Queue.new
    old_received = []
    new_received = Async::Queue.new
    final_position = final_gaps = nil

    Async do |task|
      old_channel = client.realtime.channel('contract')
      old_channel.on('message') do |message|
        value = message.fetch('value')
        old_received << value
        next unless value == 2

        offset_two_started.enqueue(true)
        release_offset_two.dequeue
      end
      old_channel.subscribe
      observe_broadcast_delivery(
        old_channel,
        offset: 3,
        completed: old_offset_three_processed
      )
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 },
        epoch: 'epoch-1',
        offset: 2
      )
      task.with_timeout(0.2) { offset_two_started.dequeue }
      socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 3 },
        epoch: 'epoch-1',
        offset: 3
      )
      socket.receive_raw('{}')

      released = false
      begin
        task.with_timeout(0.2) { reader_passed_offset_three.dequeue }
        client.realtime.remove_channel('contract')
        new_channel = client.realtime.channel('contract')
        new_channel.on('message') { |message| new_received.enqueue(message.fetch('value')) }
        new_channel.subscribe

        release_offset_two.enqueue(true)
        released = true
        task.with_timeout(0.2) { old_offset_three_processed.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 11 },
          epoch: 'epoch-2',
          offset: 11
        )
        expect(task.with_timeout(0.2) { new_received.dequeue }).to eq(11)
        protocol = client.realtime.send(:protocol)
        final_position = protocol.position('broadcast:contract')
        final_gaps = protocol.instance_variable_get(:@position_gaps).dup
      ensure
        release_offset_two.enqueue(true) unless released
        client.realtime.disconnect
      end
    end.wait

    expect(old_received).to eq([2])
    expect(final_position).to eq(epoch: 'epoch-2', offset: 11)
    expect(final_gaps).not_to include('broadcast:contract')
  end

  it 'keeps immediate reader rejection independent of a same-channel send', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    first_started, release_first, release_second, reader_passed_queue_fill,
      publish_started, rejection_started, rejection_completed = Array.new(7) { Async::Queue.new }
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      if command.key?('subscribe')
        channel = command.dig('subscribe', 'channel')
        epoch = channel == 'broadcast:blocker' ? 'blocker-epoch' : 'epoch-1'
        socket.respond(
          command.fetch('id'), result: { 'epoch' => epoch, 'offset' => 0, 'publications' => [] }
        )
        :defer
      elsif command.key?('publish')
        publish_started.enqueue(
          [command.fetch('id'), command.dig('publish', 'channel')]
        )
        :defer
      elsif command.empty?
        reader_passed_queue_fill.enqueue(true)
        :defer
      end
    end
    client = realtime_client(socket)
    drops = []
    received = []
    results = {}

    Async do |task|
      blocker = client.realtime.channel('blocker')
      blocker.on('message') do |message|
        if message.fetch('value') == 'blocker-1'
          first_started.enqueue(true)
          release_first.dequeue
        else
          release_second.dequeue
        end
      end
      target = client.realtime.channel('contract')
      target.on('message') { |message| received << message.fetch('value') }
      blocker.subscribe
      target.subscribe
      protocol = client.realtime.send(:protocol)
      observe_publication_drops(protocol, channel: 'broadcast:contract', drops: drops)
      observe_immediate_reader_rejection(
        protocol,
        started: rejection_started,
        completed: rejection_completed
      )

      reply_sent = false
      reply_id = nil
      sending = nil
      begin
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-1' },
          epoch: 'blocker-epoch', offset: 1
        )
        task.with_timeout(0.5) { first_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-2' },
          epoch: 'blocker-epoch', offset: 2
        )
        socket.receive_raw('{}')
        task.with_timeout(0.5) { reader_passed_queue_fill.dequeue }
        results[:queue_full] = protocol.instance_variable_get(:@callback_queue).limited?

        sending = task.async { target.send(event: 'message', value: 'sent') }
        reply_id, results[:command_channel] = task.with_timeout(0.5) { publish_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 1 },
          epoch: 'epoch-1', offset: 1
        )
        results[:rejection] = task.with_timeout(0.5) { rejection_started.dequeue }
        task.with_timeout(0.5) { rejection_completed.dequeue }
        results[:drops_before_reply] = drops.dup
        results[:gaps_before_reply] = protocol.instance_variable_get(:@position_gaps).dup

        socket.respond(reply_id)
        reply_sent = true
        results[:command_result] = task.with_timeout(0.5) { sending.wait }
      ensure
        sending&.stop
        socket.respond(reply_id) if reply_id && !reply_sent
        release_first.enqueue(true)
        release_second.enqueue(true)
        client.realtime.disconnect
      end
    end.wait

    expect(results).to include(
      queue_full: true,
      command_channel: 'broadcast:contract',
      rejection: ['broadcast:contract', 1, true, true, 0],
      drops_before_reply: [1],
      command_result: nil
    )
    expect(results.fetch(:gaps_before_reply)).to eq(
      'broadcast:contract' => { epoch: 'epoch-1', offset: 1 }
    )
    expect(received).to be_empty
  end

  it 'ignores a delayed old-generation producer rejection after resubscribe', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    replacement = { 'epoch' => 'epoch-2', 'offset' => 10, 'publications' => [] }
    socket, restored_socket, reader_passed_queue_fill, client =
      reconnecting_delayed_rejection_client(replacement:)
    first_started, release_first, second_started, release_second,
      producer_waiting, live_queued, rejection_started, rejection_completed,
      old_recovery_processed, current_received = Array.new(10) { Async::Queue.new }
    drops = []
    results = {}

    Async do |task|
      blocker = client.realtime.channel('blocker')
      blocker.on('message') do |message|
        case message.fetch('value')
        when 'blocker-1'
          first_started.enqueue(true)
          release_first.dequeue
        when 'blocker-2'
          second_started.enqueue(true)
          release_second.dequeue
        end
      end
      target = client.realtime.channel('contract')
      target.on('message') { |message| current_received.enqueue(message.fetch('value')) }
      blocker.subscribe
      protocol = client.realtime.send(:protocol)
      observe_publication_drops(protocol, channel: 'broadcast:contract', drops: drops)
      observation = DelayedProducerObservation.new(
        channel: 'broadcast:contract',
        recovery_offset: 2,
        live_offset: 3,
        producer_waiting: producer_waiting,
        live_queued: live_queued,
        rejection_started: rejection_started,
        rejection_completed: rejection_completed
      )
      observe_delayed_producer_rejection(protocol, observation)
      observe_broadcast_delivery(target, offset: 2, completed: old_recovery_processed)

      first_released = second_released = false
      begin
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-1' },
          epoch: 'blocker-epoch', offset: 1
        )
        task.with_timeout(0.5) { first_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-2' },
          epoch: 'blocker-epoch', offset: 2
        )
        socket.receive_raw('{}')
        task.with_timeout(0.5) { reader_passed_queue_fill.dequeue }
        expect(protocol.instance_variable_get(:@callback_queue)).to be_limited

        target.subscribe
        expect(task.with_timeout(0.5) { producer_waiting.dequeue }).to eq([true, false, true])
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 3 },
          epoch: 'epoch-1', offset: 3
        )
        expect(task.with_timeout(0.5) { live_queued.dequeue }).to eq(2)

        target.unsubscribe
        target.subscribe
        results[:replacement_position] = protocol.position('broadcast:contract')

        release_first.enqueue(true)
        first_released = true
        task.with_timeout(0.5) { second_started.dequeue }
        expect(task.with_timeout(0.5) { rejection_started.dequeue }).to eq([true, true, true])
        task.with_timeout(0.5) { rejection_completed.dequeue }
        results[:drops_after_rejection] = drops.dup
        results[:gaps_after_rejection] = protocol.instance_variable_get(:@position_gaps).dup

        release_second.enqueue(true)
        second_released = true
        task.with_timeout(0.5) { old_recovery_processed.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 11 },
          epoch: 'epoch-2', offset: 11
        )
        results[:received] = task.with_timeout(0.5) { current_received.dequeue }
        results[:position] = protocol.position('broadcast:contract')
        results[:gaps] = protocol.instance_variable_get(:@position_gaps).dup

        socket.fail_read(IOError.new('socket failed'))
        task.with_timeout(0.5) do
          task.yield until restored_socket.commands.any? do |command|
            command.dig('subscribe', 'channel') == 'broadcast:contract'
          end
        end
      ensure
        release_first.enqueue(true) unless first_released
        release_second.enqueue(true) unless second_released
        client.realtime.disconnect
      end
    end.wait

    expect(results).to include(
      replacement_position: { epoch: 'epoch-2', offset: 10 },
      drops_after_rejection: [], received: 11,
      position: { epoch: 'epoch-2', offset: 11 }
    )
    expect(results.fetch(:gaps_after_rejection)).not_to include('broadcast:contract')
    expect(results.fetch(:gaps)).not_to include('broadcast:contract')
    expect_reconnect_position(restored_socket, epoch: 'epoch-2', offset: 11)
  end

  it 'ignores a delayed old-generation producer rejection after remove and recreate', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    replacement = { 'epoch' => 'epoch-2', 'offset' => 10, 'publications' => [] }
    socket, reader_passed_queue_fill = delayed_rejection_socket(replacement:)
    client = realtime_client(socket)
    first_started, release_first, second_started, release_second,
      producer_waiting, live_queued, rejection_started, rejection_completed,
      old_recovery_processed, current_received = Array.new(10) { Async::Queue.new }
    drops = []
    old_received = []
    results = {}

    Async do |task|
      blocker = client.realtime.channel('blocker')
      blocker.on('message') do |message|
        case message.fetch('value')
        when 'blocker-1'
          first_started.enqueue(true)
          release_first.dequeue
        when 'blocker-2'
          second_started.enqueue(true)
          release_second.dequeue
        end
      end
      old_target = client.realtime.channel('contract')
      old_target.on('message') { |message| old_received << message.fetch('value') }
      blocker.subscribe
      protocol = client.realtime.send(:protocol)
      observe_publication_drops(protocol, channel: 'broadcast:contract', drops: drops)
      observation = DelayedProducerObservation.new(
        channel: 'broadcast:contract',
        recovery_offset: 2,
        live_offset: 3,
        producer_waiting: producer_waiting,
        live_queued: live_queued,
        rejection_started: rejection_started,
        rejection_completed: rejection_completed
      )
      observe_delayed_producer_rejection(protocol, observation)
      observe_broadcast_delivery(old_target, offset: 2, completed: old_recovery_processed)

      first_released = second_released = false
      begin
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-1' },
          epoch: 'blocker-epoch', offset: 1
        )
        task.with_timeout(0.5) { first_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-2' },
          epoch: 'blocker-epoch', offset: 2
        )
        socket.receive_raw('{}')
        task.with_timeout(0.5) { reader_passed_queue_fill.dequeue }
        expect(protocol.instance_variable_get(:@callback_queue)).to be_limited

        old_target.subscribe
        expect(task.with_timeout(0.5) { producer_waiting.dequeue }).to eq([true, false, true])
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 3 },
          epoch: 'epoch-1', offset: 3
        )
        expect(task.with_timeout(0.5) { live_queued.dequeue }).to eq(2)

        client.realtime.remove_channel('contract')
        new_target = client.realtime.channel('contract')
        new_target.on('message') { |message| current_received.enqueue(message.fetch('value')) }
        new_target.subscribe
        results[:replacement_position] = protocol.position('broadcast:contract')

        release_first.enqueue(true)
        first_released = true
        task.with_timeout(0.5) { second_started.dequeue }
        expect(task.with_timeout(0.5) { rejection_started.dequeue }).to eq([true, true, true])
        task.with_timeout(0.5) { rejection_completed.dequeue }
        results[:drops_after_rejection] = drops.dup
        results[:gaps_after_rejection] = protocol.instance_variable_get(:@position_gaps).dup

        release_second.enqueue(true)
        second_released = true
        task.with_timeout(0.5) { old_recovery_processed.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 11 },
          epoch: 'epoch-2', offset: 11
        )
        results[:received] = task.with_timeout(0.5) { current_received.dequeue }
        results[:position] = protocol.position('broadcast:contract')
        results[:gaps] = protocol.instance_variable_get(:@position_gaps).dup
      ensure
        release_first.enqueue(true) unless first_released
        release_second.enqueue(true) unless second_released
        client.realtime.disconnect
      end
    end.wait

    expect(old_received).to be_empty
    expect(results).to include(
      replacement_position: { epoch: 'epoch-2', offset: 10 },
      drops_after_rejection: [], received: 11,
      position: { epoch: 'epoch-2', offset: 11 }
    )
    expect(results.fetch(:gaps_after_rejection)).not_to include('broadcast:contract')
    expect(results.fetch(:gaps)).not_to include('broadcast:contract')
  end

  it 'records one gap for a delayed current-generation producer rejection', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    socket, reader_passed_queue_fill = delayed_rejection_socket
    client = realtime_client(socket)
    first_started, release_first, second_started, release_second,
      producer_waiting, live_queued, rejection_started, rejection_completed,
      target_received = Array.new(9) { Async::Queue.new }
    drops = []
    results = {}

    Async do |task|
      blocker = client.realtime.channel('blocker')
      blocker.on('message') do |message|
        case message.fetch('value')
        when 'blocker-1'
          first_started.enqueue(true)
          release_first.dequeue
        when 'blocker-2'
          second_started.enqueue(true)
          release_second.dequeue
        end
      end
      target = client.realtime.channel('contract')
      target.on('message') { |message| target_received.enqueue(message.fetch('value')) }
      blocker.subscribe
      protocol = client.realtime.send(:protocol)
      observe_publication_drops(protocol, channel: 'broadcast:contract', drops: drops)
      observation = DelayedProducerObservation.new(
        channel: 'broadcast:contract',
        recovery_offset: 2,
        live_offset: 3,
        producer_waiting: producer_waiting,
        live_queued: live_queued,
        rejection_started: rejection_started,
        rejection_completed: rejection_completed
      )
      observe_delayed_producer_rejection(protocol, observation)

      first_released = second_released = false
      begin
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-1' },
          epoch: 'blocker-epoch', offset: 1
        )
        task.with_timeout(0.5) { first_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-2' },
          epoch: 'blocker-epoch', offset: 2
        )
        socket.receive_raw('{}')
        task.with_timeout(0.5) { reader_passed_queue_fill.dequeue }
        expect(protocol.instance_variable_get(:@callback_queue)).to be_limited

        target.subscribe
        expect(task.with_timeout(0.5) { producer_waiting.dequeue }).to eq([true, false, true])
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 3 },
          epoch: 'epoch-1', offset: 3
        )
        expect(task.with_timeout(0.5) { live_queued.dequeue }).to eq(2)

        release_first.enqueue(true)
        first_released = true
        task.with_timeout(0.5) { second_started.dequeue }
        expect(task.with_timeout(0.5) { rejection_started.dequeue }).to eq([true, true, true])
        task.with_timeout(0.5) { rejection_completed.dequeue }

        release_second.enqueue(true)
        second_released = true
        results[:recovered] = task.with_timeout(0.5) { target_received.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 4 },
          epoch: 'epoch-1', offset: 4
        )
        results[:later] = task.with_timeout(0.5) { target_received.dequeue }
        results[:drops] = drops.dup
        results[:position] = protocol.position('broadcast:contract')
        results[:gaps] = protocol.instance_variable_get(:@position_gaps).dup
      ensure
        release_first.enqueue(true) unless first_released
        release_second.enqueue(true) unless second_released
        client.realtime.disconnect
      end
    end.wait

    expect(results).to include(
      recovered: 2, later: 4, drops: [3],
      position: { epoch: 'epoch-1', offset: 2 }
    )
    expect(results.fetch(:gaps)).to eq(
      'broadcast:contract' => { epoch: 'epoch-1', offset: 3 }
    )
  end

  it 'reconnects from the delivered cursor when a recovered batch saturates the ordered queue' do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    socket, restored_socket = Array.new(2) { FacadeSocket.new }
    reader_passed_queue_fill, recovery_requested = Array.new(2) { Async::Queue.new }
    target_results = [
      { 'epoch' => 'epoch-1', 'offset' => 1, 'publications' => [] },
      {
        'epoch' => 'epoch-1', 'offset' => 2,
        'publications' => [
          { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } }
        ]
      },
      {
        'epoch' => 'epoch-1', 'offset' => 3,
        'publications' => [
          { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } },
          { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }
        ]
      }
    ]
    socket.on_write = lambda do |command|
      if command.key?('subscribe')
        channel = command.dig('subscribe', 'channel')
        result = if channel == 'broadcast:blocker'
                   { 'epoch' => 'blocker-epoch', 'offset' => 0, 'publications' => [] }
                 else
                   target_results.shift
                 end
        socket.respond(command.fetch('id'), result: result)
        :defer
      elsif command.key?('unsubscribe')
        socket.respond(command.fetch('id'))
        :defer
      elsif command.empty?
        reader_passed_queue_fill.enqueue(true)
        :defer
      end
    end
    restored_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      if command.dig('subscribe', 'channel') == 'broadcast:blocker'
        restored_socket.respond(
          command.fetch('id'),
          result: { 'epoch' => 'blocker-epoch', 'offset' => 1, 'publications' => [] }
        )
      else
        recovery_requested.enqueue(command)
      end
      :defer
    end
    client = reconnecting_realtime_client([socket, restored_socket])
    blocker_started, release_blocker, producer_waiting, live_queued,
      saturation_observed, unused_rejection_started, unused_rejection_completed,
      received = Array.new(8) { Async::Queue.new }
    results = {}

    Async do |task|
      blocker = client.realtime.channel('blocker')
      blocker.on('message') do |message|
        next unless message.fetch('value') == 'blocker-1'

        blocker_started.enqueue(true)
        release_blocker.dequeue
      end
      target = client.realtime.channel('contract')
      target.on('message') { |message| received.enqueue(message.fetch('value')) }
      blocker.subscribe
      target.subscribe
      protocol = client.realtime.send(:protocol)
      observation = DelayedProducerObservation.new(
        channel: 'broadcast:contract', recovery_offset: 2, live_offset: 3,
        producer_waiting:, live_queued:,
        rejection_started: unused_rejection_started,
        rejection_completed: unused_rejection_completed
      )
      observe_delayed_producer_rejection(protocol, observation)
      observe_recovered_queue_saturation(
        protocol, channel: 'broadcast:contract', observed: saturation_observed
      )

      saturated_subscription = nil
      begin
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-1' },
          epoch: 'blocker-epoch', offset: 1
        )
        task.with_timeout(0.5) { blocker_started.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:blocker',
          data: { 'event' => 'message', 'value' => 'blocker-2' },
          epoch: 'blocker-epoch', offset: 2
        )
        socket.receive_raw('{}')
        task.with_timeout(0.5) { reader_passed_queue_fill.dequeue }

        target.unsubscribe
        target.subscribe
        results[:producer_waiting] = task.with_timeout(0.5) { producer_waiting.dequeue }
        socket.publication(
          channel: 'project-id:broadcast:contract',
          data: { 'event' => 'message', 'value' => 3 },
          epoch: 'epoch-1', offset: 3
        )
        results[:live_count] = task.with_timeout(0.5) { live_queued.dequeue }

        target.unsubscribe
        saturated_subscription = task.async do
          target.subscribe
        rescue StandardError => e
          e
        end
        results[:saturation] = task.with_timeout(0.5) { saturation_observed.dequeue }
        failure = task.with_timeout(0.5) { saturated_subscription.wait }
        expect(failure).to be_a(Volcano::Realtime::ClosedError)

        recovery = task.with_timeout(0.5) { recovery_requested.dequeue }
        results[:failure] = [failure.class, failure.message]
        results[:protocol_connected] = protocol.connected?
        results[:socket_closed] = socket.closed?
        results[:received_before_recovery] = received.size
        results[:recovery_request] = recovery.fetch('subscribe')

        restored_socket.respond(
          recovery.fetch('id'),
          result: {
            'epoch' => 'epoch-1', 'offset' => 3,
            'publications' => [
              { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } },
              { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }
            ]
          }
        )
        results[:received] = task.with_timeout(0.5) { Array.new(2) { received.dequeue } }
      ensure
        saturated_subscription&.stop
        release_blocker.enqueue(true)
        client.realtime.disconnect
      end
    end.wait

    limit_message = 'realtime recovered publication queue limit 1 reached'
    expect(results).to eq(
      producer_waiting: [true, false, true],
      live_count: 2,
      saturation: {
        reader: true,
        queue_sizes: [1, 1],
        ordered_count: 2
      },
      failure: [Volcano::Realtime::ClosedError, limit_message],
      protocol_connected: false,
      socket_closed: true,
      received_before_recovery: 0,
      recovery_request: {
        'channel' => 'broadcast:contract',
        'recover' => true,
        'positioned' => true,
        'recoverable' => true,
        'epoch' => 'epoch-1',
        'offset' => 1
      },
      received: [2, 3]
    )
  end

  it 'retains the delivered initial recovery position for the next reconnect' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(
        command.fetch('id'),
        result: {
          'epoch' => 'epoch-1',
          'offset' => 3,
          'publications' => [
            { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 'retained-2' } },
            { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 'retained-3' } }
          ]
        }
      )
      :defer
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message) }
      channel.subscribe
      task.with_timeout(0.2) { Array.new(2) { received.dequeue } }

      first_socket.fail_read(IOError.new('socket failed'))
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    initial_subscribe = first_socket.commands.find { |command| command.key?('subscribe') }
    expect(initial_subscribe.fetch('subscribe')).to eq(
      'channel' => 'broadcast:contract',
      'recover' => true,
      'positioned' => true,
      'recoverable' => true
    )
    restored_subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(restored_subscribe.fetch('subscribe')).to include(
      'channel' => 'broadcast:contract',
      'recover' => true,
      'epoch' => 'epoch-1',
      'offset' => 3
    )
  end

  it 'starts broadcast recovery over for a different authenticated user' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 1 })
      :defer
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: lambda do |_attempt|
        reconnect_waiting.enqueue(true)
        allow_reconnect.dequeue
        0
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      channel.subscribe
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 },
        epoch: 'epoch-1',
        offset: 2
      )
      task.with_timeout(0.2) { received.dequeue }

      first_socket.fail_read(IOError.new('socket failed'))
      reconnect_waiting.dequeue
      client.store_session(
        Volcano::Session.new(
          access_token: 'other-access', refresh_token: 'other-refresh', user_id: 'other-user'
        )
      )
      allow_reconnect.enqueue(true)
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to eq(
      'channel' => 'broadcast:contract',
      'recover' => true,
      'positioned' => true,
      'recoverable' => true
    )
  end

  it 'retains broadcast recovery for a token refresh in the same user lineage' do
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    first_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      first_socket.respond(command.fetch('id'), result: { 'epoch' => 'epoch-1', 'offset' => 1 })
      :defer
    end
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: lambda do |_attempt|
        reconnect_waiting.enqueue(true)
        allow_reconnect.dequeue
        0
      end
    )
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      channel.subscribe
      first_socket.publication(
        channel: 'project-id:broadcast:contract',
        data: { 'event' => 'message', 'value' => 2 },
        epoch: 'epoch-1',
        offset: 2
      )
      task.with_timeout(0.2) { received.dequeue }

      first_socket.fail_read(IOError.new('socket failed'))
      reconnect_waiting.dequeue
      client.store_session(
        Volcano::Session.new(
          access_token: 'access-refreshed', refresh_token: 'refresh-token', user_id: 'user-123'
        ),
        event: :token_refreshed
      )
      allow_reconnect.enqueue(true)
      task.with_timeout(0.2) do
        task.yield until restored_socket.commands.any? { |command| command.key?('subscribe') }
      end
      client.realtime.disconnect
    end.wait

    subscribe = restored_socket.commands.find { |command| command.key?('subscribe') }
    expect(subscribe.fetch('subscribe')).to include(
      'channel' => 'broadcast:contract',
      'recover' => true,
      'epoch' => 'epoch-1',
      'offset' => 2
    )
  end

  it 'delivers recovered broadcasts before a same-frame live broadcast' do
    socket = FacadeSocket.new
    socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      reply = JSON.generate(
        'id' => command.fetch('id'),
        'result' => {
          'epoch' => 'epoch-1',
          'offset' => 3,
          'publications' => [
            { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } },
            { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }
          ]
        }
      )
      live = JSON.generate(
        'push' => {
          'channel' => 'project-id:broadcast:contract',
          'pub' => {
            'epoch' => 'epoch-1',
            'offset' => 4,
            'data' => { 'event' => 'message', 'value' => 4 }
          }
        }
      )
      socket.receive_raw("#{reply}\n#{live}")
      :defer
    end
    client = realtime_client(socket)
    received = Async::Queue.new

    Async do |task|
      channel = client.realtime.channel('contract')
      channel.on('message') { |message| received.enqueue(message.fetch('value')) }
      channel.subscribe

      expect(task.with_timeout(0.2) { Array.new(3) { received.dequeue } }).to eq([2, 3, 4])
      client.realtime.disconnect
    end.wait
  end

  it 'preserves exact non-broadcast subscription commands' do
    presence_socket = FacadeSocket.new
    postgres_socket = FacadeSocket.new
    presence_client = realtime_client(presence_socket)
    postgres_client = realtime_client(postgres_socket)

    Async do
      presence_client.realtime.channel('lobby', type: :presence).subscribe
      postgres_client.realtime.channel('public:messages', type: :postgres).subscribe
      presence_client.realtime.disconnect
      postgres_client.realtime.disconnect
    end.wait

    presence_subscribe = presence_socket.commands.find { |command| command.key?('subscribe') }
    expect(presence_subscribe).to eq(
      'id' => 2,
      'subscribe' => {
        'channel' => 'presence:lobby',
        'recoverable' => true,
        'join_leave' => true
      }
    )
    postgres_subscribe = postgres_socket.commands.find { |command| command.key?('subscribe') }
    expect(postgres_subscribe).to eq(
      'id' => 2,
      'subscribe' => { 'channel' => 'postgres:public:messages' }
    )
  end

  it 'does not restore a channel unsubscribed during an outage' do
    first_socket = FacadeSocket.new
    second_socket = FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    sockets = [first_socket, second_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
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
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    failed_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    failed_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      failed_socket.fail_read(IOError.new('restore failed'))
      :defer
    end
    sockets = [first_socket, failed_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
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
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    reconnect_waiting = Async::Queue.new
    allow_reconnect = Async::Queue.new
    sockets = [first_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    failed_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
    failed_socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      reply = JSON.generate('id' => command.fetch('id'), 'result' => {})
      failed_socket.receive_raw("#{reply}\n{")
      :defer
    end
    sockets = [failed_socket, restored_socket]
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    first_socket = FacadeSocket.new
    restored_socket = FacadeSocket.new
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
      _transport: RealtimeAuthTransport.new,
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
      _transport: RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { FacadeSocket.new }
    )

    expect { client.realtime.channel('contract').remove }.to raise_error(NoMethodError)
  end

  it 'removes an inactive channel without connecting', :aggregate_failures do
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    addresses = []
    client = Volcano::Client.new(
      api_url: 'https://api.test.volcano.dev/volcano/',
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    connect_written = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('connect')

      connect_written.enqueue(command.fetch('id'))
      :defer
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
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
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('subscribe')

      entered.enqueue(true)
      release.dequeue
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
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
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    factory = lambda do |_address|
      entered.enqueue(true)
      release.dequeue
      socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
    socket = FacadeSocket.new
    entered = Async::Queue.new
    release = Async::Queue.new
    factory = lambda do |_address|
      entered.enqueue(true)
      release.dequeue
      socket
    end
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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
