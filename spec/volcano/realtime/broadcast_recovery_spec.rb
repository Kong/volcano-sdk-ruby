# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'

BroadcastRecovery = Volcano::Realtime

class BroadcastRecoverySocket
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

    result = command.key?('connect') ? { 'client' => 'client-123' } : default_result(command)
    respond(command.fetch('id'), result: result)
  end

  def read
    value = @incoming.dequeue
    raise value if value.is_a?(Exception)

    value
  end

  def respond(id, result: {}) = @incoming.enqueue(JSON.generate('id' => id, 'result' => result))

  def receive(*frames) = @incoming.enqueue(frames.map { |frame| JSON.generate(frame) }.join("\n"))

  def fail_read(error) = @incoming.enqueue(error)

  def publication(channel:, offset:, value:, epoch: 'epoch-1', event: 'message')
    receive(
      'push' => {
        'channel' => channel,
        'pub' => publication_payload(offset:, value:, epoch:, event:)
      }
    )
  end

  def close
    return if @closed

    @closed = true
    @incoming.enqueue(nil)
  end

  private

  def default_result(command)
    return { 'epoch' => 'epoch-1', 'offset' => 0, 'publications' => [] } if command.key?('subscribe')

    {}
  end

  def publication_payload(offset:, value:, epoch:, event:)
    {
      'epoch' => epoch,
      'offset' => offset,
      'data' => { 'event' => event, 'value' => value }
    }
  end
end

RSpec.describe BroadcastRecovery do
  around do |example|
    Async { example.run }.wait
  end

  it 'starts a first broadcast subscription at an empty recoverable position' do
    socket = BroadcastRecoverySocket.new
    client = recovery_client([socket])

    subscribe(client)

    expect(subscribe_options(socket)).to eq(empty_recovery_options)
  ensure
    disconnect(client)
  end

  it 'reconnects a broadcast from its last delivered position' do
    first, restored = recovery_sockets(2)
    client = recovery_client([first, restored])
    received = Async::Queue.new
    subscribe(client, received:)
    publish_and_wait(first, received, offset: 1)

    reconnect(first, restored)

    expect(subscribe_options(restored)).to include('epoch' => 'epoch-1', 'offset' => 1)
  ensure
    disconnect(client)
  end

  it 'delivers a recovered batch before a later live publication in the same frame' do
    socket = BroadcastRecoverySocket.new
    socket.on_write = recovery_then_live(socket)
    client = recovery_client([socket])
    received = Async::Queue.new

    subscribe(client, received:)

    expect(dequeue(received, 3)).to eq([1, 2, 3])
  ensure
    disconnect(client)
  end

  it 'uses the delivered initial retained baseline on the next reconnect' do
    first, restored = recovery_sockets(2)
    first.on_write = retained_reply(first, retained(1), retained(2))
    client = recovery_client([first, restored])
    received = Async::Queue.new

    subscribe(client, received:)
    expect(dequeue(received, 2)).to eq([1, 2])
    reconnect(first, restored)

    expect(subscribe_options(restored)).to include('epoch' => 'epoch-1', 'offset' => 2)
  ensure
    disconnect(client)
  end

  it 'reuses the delivered position after explicit unsubscribe and resubscribe' do
    socket = BroadcastRecoverySocket.new
    client = recovery_client([socket])
    received = Async::Queue.new
    channel = subscribe(client, received:)
    publish_and_wait(socket, received, offset: 1)

    channel.unsubscribe
    channel.subscribe

    expect(subscribe_options(socket, index: 1)).to include('epoch' => 'epoch-1', 'offset' => 1)
  ensure
    disconnect(client)
  end

  it 'starts over after a channel is removed and recreated' do
    socket = BroadcastRecoverySocket.new
    client = recovery_client([socket])
    received = Async::Queue.new
    subscribe(client, received:)
    publish_and_wait(socket, received, offset: 1)

    client.realtime.remove_channel('contract')
    subscribe(client)

    expect(subscribe_options(socket, index: 1)).to eq(empty_recovery_options)
  ensure
    disconnect(client)
  end

  it 'does not advance past malformed retained publications' do
    socket = BroadcastRecoverySocket.new
    replies = [baseline(1), malformed_retained_result, baseline(1)]
    socket.on_write = sequential_subscribe_replies(socket, replies)
    client = recovery_client([socket])
    channel = subscribe(client)

    channel.unsubscribe
    channel.subscribe
    channel.unsubscribe
    channel.subscribe

    expect(subscribe_options(socket, index: 2)).to include('epoch' => 'epoch-1', 'offset' => 1)
  ensure
    disconnect(client)
  end

  it 'does not advance across skipped retained offsets' do
    first, second, third = recovery_sockets(3)
    first.on_write = reply_with(first, baseline(2))
    second.on_write = retained_reply(second, retained(4), result_offset: 4)
    client = recovery_client([first, second, third])
    received = Async::Queue.new
    subscribe(client, received:)

    reconnect(first, second)
    expect(dequeue(received)).to eq([4])
    reconnect(second, third)

    expect(subscribe_options(third)).to include('epoch' => 'epoch-1', 'offset' => 2)
  ensure
    disconnect(client)
  end

  it 'waits through callback saturation without discarding recovered broadcasts' do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    socket = BroadcastRecoverySocket.new
    client = recovery_client([socket])
    entered = Async::Queue.new
    release = Async::Queue.new
    values = Async::Queue.new
    prepare_callback_saturation(client, socket, entered, release, values)

    expect(dequeue(values, 2)).to eq([1, 2])
  ensure
    release&.enqueue(true)
    disconnect(client)
  end

  it 'requests the delivered cursor when producer saturation rejects recovery' do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    socket = BroadcastRecoverySocket.new
    client = recovery_client([socket])

    saturate_recovered_producer(client, socket)

    expect(subscribe_options(socket, index: 3)).to include(
      'epoch' => 'epoch-1', 'offset' => 1
    )
  ensure
    disconnect(client)
  end

  it 'reconnects from only the retained publications delivered before transport loss' do
    first, restored = recovery_sockets(2)
    release = Async::Queue.new
    first.on_write = retained_reply(first, retained(1), retained(2))
    client = recovery_client([first, restored])
    delivered = Async::Queue.new
    partial_delivery_channel(client, delivered, release)
    expect(dequeue(delivered)).to eq([1])

    first.fail_read(IOError.new('socket failed'))
    release.enqueue(true)
    wait_for_subscribe(restored)

    expect(subscribe_options(restored)).to include('epoch' => 'epoch-1', 'offset' => 1)
  ensure
    release&.enqueue(true)
    disconnect(client)
  end

  it 'keeps the recovery position across a same-user token refresh' do
    first, restored = recovery_sockets(2)
    waiting, resume = async_queues(2)
    client = recovery_client([first, restored], reconnect_gate: [waiting, resume])
    received = Async::Queue.new
    subscribe(client, received:)
    publish_and_wait(first, received, offset: 1)

    change_session_during_reconnect(client, [first, restored], [waiting, resume], refreshed_session)

    expect(subscribe_options(restored)).to include('epoch' => 'epoch-1', 'offset' => 1)
  ensure
    disconnect(client)
  end

  it 'resets the recovery position for a different authenticated user' do
    first, restored = recovery_sockets(2)
    waiting, resume = async_queues(2)
    client = recovery_client([first, restored], reconnect_gate: [waiting, resume])
    received = Async::Queue.new
    subscribe(client, received:)
    publish_and_wait(first, received, offset: 1)

    change_session_during_reconnect(client, [first, restored], [waiting, resume], other_user_session)

    expect(subscribe_options(restored)).to eq(empty_recovery_options)
  ensure
    disconnect(client)
  end

  it 'does not persist recovery state across client instances' do
    first, second = recovery_sockets(2)
    first_client = recovery_client([first])
    received = Async::Queue.new
    subscribe(first_client, received:)
    publish_and_wait(first, received, offset: 1)
    disconnect(first_client)

    second_client = recovery_client([second])
    subscribe(second_client)

    expect(subscribe_options(second)).to eq(empty_recovery_options)
  ensure
    disconnect(first_client)
    disconnect(second_client)
  end

  it 'preserves exact presence and Postgres subscribe frames without ledger entries' do
    presence_socket, postgres_socket = recovery_sockets(2)
    presence_client = recovery_client([presence_socket])
    postgres_client = recovery_client([postgres_socket])

    subscribe(presence_client, type: :presence, name: 'lobby')
    subscribe(postgres_client, type: :postgres, name: 'public:messages')

    expect(subscribe_command(presence_socket)).to eq(presence_subscribe_frame)
    expect(subscribe_command(postgres_socket)).to eq(postgres_subscribe_frame)
    expect(recovery_ledgers(presence_client)).to eq([{}, {}])
    expect(recovery_ledgers(postgres_client)).to eq([{}, {}])
  ensure
    disconnect(presence_client)
    disconnect(postgres_client)
  end

  private

  def recovery_client(sockets, reconnect_gate: nil)
    client = Volcano::Client.new(
      anon_key: 'anon-key', _transport: Object.new,
      _realtime_socket_factory: ->(_address) { sockets.shift },
      _realtime_reconnect_delay: reconnect_delay(reconnect_gate)
    )
    client.store_session(session('access-token', 'user-123'))
    client
  end

  def reconnect_delay(gate)
    return ->(_attempt) { 0 } unless gate

    waiting, resume = gate
    ->(_attempt) { waiting.enqueue(true).then { resume.dequeue }.then { 0 } }
  end

  def subscribe(client, received: nil, type: :broadcast, name: 'contract')
    channel = client.realtime.channel(name, type:)
    channel.on('message', ->(message) { received.enqueue(message.fetch('value')) }) if received
    channel.subscribe
    channel
  end

  def publish_and_wait(socket, received, offset:)
    socket.publication(channel: 'project-id:broadcast:contract', offset:, value: offset)
    expect(dequeue(received)).to eq([offset])
  end

  def reconnect(failed, restored)
    failed.fail_read(IOError.new('socket failed'))
    wait_for_subscribe(restored)
  end

  def wait_for_subscribe(socket)
    Async::Task.current.with_timeout(0.5) do
      Async::Task.current.yield until socket.commands.any? { |command| command.key?('subscribe') }
    end
  end

  def recovery_then_live(socket)
    lambda do |command|
      next unless command.key?('subscribe')

      socket.receive(
        reply(command, baseline(2, publications: [retained(1), retained(2)])),
        push(retained(3))
      )
      :defer
    end
  end

  def retained_reply(socket, *publications, result_offset: publications.last.fetch('offset'))
    reply_with(socket, baseline(result_offset, publications: publications))
  end

  def reply_with(socket, result)
    lambda do |command|
      next unless command.key?('subscribe')

      socket.respond(command.fetch('id'), result: result)
      :defer
    end
  end

  def sequential_subscribe_replies(socket, replies)
    lambda do |command|
      next unless command.key?('subscribe')

      socket.respond(command.fetch('id'), result: replies.shift)
      :defer
    end
  end

  def prepare_callback_saturation(client, socket, entered, release, values)
    callback_blocker(client, entered, release)
    target = recovery_target(client, values)
    fill_callback_queue(socket, entered)
    socket.on_write = retained_reply(socket, retained(1), retained(2))
    target.subscribe
    release.enqueue(true)
  end

  def callback_blocker(client, entered, release)
    client.realtime.channel('blocker').tap do |channel|
      channel.on('message') do |message|
        next unless message.fetch('value') == 'block'

        entered.enqueue(true)
        release.dequeue
      end
      channel.subscribe
    end
  end

  def recovery_target(client, values)
    client.realtime.channel('contract').tap do |channel|
      channel.on('message') { |message| values.enqueue(message.fetch('value')) }
    end
  end

  def fill_callback_queue(socket, entered)
    socket.publication(channel: 'broadcast:blocker', offset: 1, value: 'block')
    entered.dequeue
    socket.publication(channel: 'broadcast:blocker', offset: 2, value: 'queued')
  end

  def saturate_recovered_producer(client, socket)
    blocker_entered, blocker_release, recovery_entered, recovery_release = async_queues(4)
    blocker = blocking_channel(client, 'blocker', blocker_entered, blocker_release)
    target = blocking_recovery_channel(client, recovery_entered, recovery_release)
    establish_saturated_target(
      client, socket, [blocker, target], [blocker_entered, recovery_entered]
    )
    fill_producer_queue(socket, target)
    expect_saturated_recovery(socket, target)
  ensure
    2.times { blocker_release&.enqueue(true) }
    recovery_release&.enqueue(true)
  end

  def establish_saturated_target(client, socket, channels, entered)
    blocker, target = channels
    blocker_entered, recovery_entered = entered
    blocker.subscribe
    establish_target_cursor(socket, target, recovery_entered)
    publish_blockers(socket, blocker_entered)
    target.unsubscribe
    socket.on_write = retained_reply(socket, retained(2), retained(3))
    target.subscribe
    wait_for_queue_drain(client)
  end

  def establish_target_cursor(socket, target, entered)
    target.subscribe
    socket.publication(channel: 'broadcast:contract', offset: 1, value: 1)
    entered.dequeue
  end

  def fill_producer_queue(socket, target)
    socket.publication(channel: 'broadcast:contract', offset: 4, value: 4)
    target.unsubscribe
  end

  def expect_saturated_recovery(socket, target)
    socket.on_write = retained_reply(socket, retained(2))
    expect { target.subscribe }.to raise_error(Volcano::Realtime::PendingLimitError)
  end

  def blocking_channel(client, name, entered, release)
    client.realtime.channel(name).tap do |channel|
      channel.on('message') do |message|
        entered.enqueue(message.fetch('value'))
        release.dequeue
      end
    end
  end

  def blocking_recovery_channel(client, entered, release)
    client.realtime.channel('contract').tap do |channel|
      channel.on('message') do |message|
        value = message.fetch('value')
        entered.enqueue(value)
        release.dequeue unless value == 1
      end
    end
  end

  def publish_blockers(socket, entered)
    socket.publication(channel: 'broadcast:blocker', offset: 1, value: 1)
    entered.dequeue
    socket.publication(channel: 'broadcast:blocker', offset: 2, value: 2)
  end

  def wait_for_queue_drain(client)
    protocol = client.realtime.send(:protocol)
    Async::Task.current.with_timeout(0.5) do
      Async::Task.current.yield until protocol.instance_variable_get(:@publication_queue).empty?
    end
  end

  def hold_first(message, delivered, release)
    delivered.enqueue(message.fetch('value'))
    release.dequeue if message.fetch('value') == 1
  end

  def partial_delivery_channel(client, delivered, release)
    client.realtime.channel('contract').tap do |channel|
      channel.on('message') { |message| hold_first(message, delivered, release) }
      channel.subscribe
    end
  end

  def change_session_during_reconnect(client, sockets, gates, replacement)
    failed, restored = sockets
    waiting, resume = gates
    failed.fail_read(IOError.new('socket failed'))
    waiting.dequeue
    event = replacement.user_id == 'user-123' ? :token_refreshed : :signed_in
    client.store_session(replacement, event:)
    resume.enqueue(true)
    wait_for_subscribe(restored)
  end

  def subscribe_options(socket, index: 0) = subscribe_command(socket, index:).fetch('subscribe')

  def subscribe_command(socket, index: 0)
    socket.commands.select { |command| command.key?('subscribe') }.fetch(index)
  end

  def empty_recovery_options
    {
      'channel' => 'broadcast:contract',
      'recover' => true,
      'positioned' => true,
      'recoverable' => true
    }
  end

  def presence_subscribe_frame
    {
      'id' => 2,
      'subscribe' => {
        'channel' => 'presence:lobby', 'recoverable' => true, 'join_leave' => true
      }
    }
  end

  def postgres_subscribe_frame
    { 'id' => 2, 'subscribe' => { 'channel' => 'postgres:public:messages' } }
  end

  def recovery_ledgers(client)
    protocol = client.realtime.send(:protocol)
    %i[@stream_positions @position_gaps].map { |name| protocol.instance_variable_get(name) }
  end

  def baseline(offset, publications: [])
    { 'recovered' => true, 'epoch' => 'epoch-1', 'offset' => offset, 'publications' => publications }
  end

  def malformed_retained_result
    baseline(2, publications: [{ 'offset' => 'bad', 'data' => { 'event' => 'message' } }])
  end

  def retained(offset)
    {
      'epoch' => 'epoch-1', 'offset' => offset,
      'data' => { 'event' => 'message', 'value' => offset }
    }
  end

  def reply(command, result) = { 'id' => command.fetch('id'), 'result' => result }

  def push(publication)
    { 'push' => { 'channel' => 'project-id:broadcast:contract', 'pub' => publication } }
  end

  def session(access_token, user_id)
    Volcano::Session.new(access_token:, refresh_token: 'refresh-token', user_id:)
  end

  def refreshed_session = session('access-refreshed', 'user-123')
  def other_user_session = session('other-access', 'other-user')
  def recovery_sockets(count) = Array.new(count) { BroadcastRecoverySocket.new }
  def async_queues(count) = Array.new(count) { Async::Queue.new }

  def dequeue(queue, count = 1)
    Async::Task.current.with_timeout(0.5) { Array.new(count) { queue.dequeue } }
  end

  def disconnect(client)
    client&.realtime&.disconnect
  rescue Volcano::Realtime::ClosedError
    nil
  end
end
