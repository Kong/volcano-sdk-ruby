# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'

RSpec.describe Volcano::Realtime do
  RealtimeResponse = Data.define(:status, :body, :headers, :data) unless const_defined?(:RealtimeResponse)

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

    def publication(channel:, data:)
      @incoming.enqueue(
        JSON.generate(
          'push' => {
            'channel' => channel,
            'pub' => { 'data' => data }
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

  def realtime_client(socket)
    client = Volcano::Client.new(
      anon_key: 'anon-key',
      _transport: RealtimeAuthTransport.new,
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

  it 'exposes the canonical channel name' do
    client = Volcano::Client.new(anon_key: 'anon-key', _transport: RealtimeAuthTransport.new)

    expect(client.realtime.channel('contract').name).to eq('broadcast:contract')
    expect(client.realtime.channel('contract').name).to be_frozen
    expect(client.realtime.channel('lobby', type: :presence).name).to eq('presence:lobby')
    expect { client.realtime.channel('bad', type: :unknown) }.to raise_error(
      ArgumentError,
      'unsupported realtime channel type: unknown'
    )
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
