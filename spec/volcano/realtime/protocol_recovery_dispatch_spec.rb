# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'

RecoveryDispatchProtocol = Volcano::Realtime.const_get(:Protocol, false)
ProtocolRecoveryDispatch = Volcano::Realtime.const_get(:ProtocolRecoveryDispatch, false)

class RecoveryDispatchSocket
  attr_accessor :on_write
  attr_reader :close_count

  def initialize
    @incoming = Async::Queue.new
    @close_count = 0
  end

  def write(message) = on_write&.call(JSON.parse(message))

  def read = @incoming.dequeue

  def receive(*frames) = @incoming.enqueue(frames.map { |frame| JSON.generate(frame) }.join("\n"))

  def receive_raw(frame) = @incoming.enqueue(frame)

  def finish = @incoming.enqueue(nil)

  def close
    @close_count += 1
    finish
  end
end

RSpec.describe ProtocolRecoveryDispatch do
  around do |example|
    Async { example.run }.wait
  end

  let(:socket) { RecoveryDispatchSocket.new }
  let(:protocol_options) { {} }
  let(:protocol) do
    RecoveryDispatchProtocol.new(socket: socket, task: Async::Task.current, **protocol_options)
  end

  after { protocol.close }

  it 'orders a recovered batch before later live pushes across channels' do
    deliveries = Async::Queue.new
    release = Async::Queue.new
    register_ordered_handler('room-a', deliveries, release)
    protocol.on_publication('room-b') { |_event, data, *, **| deliveries.enqueue(data.fetch('value')) }
    socket.on_write = ->(command) { receive_recovery_and_live(command) }

    result = protocol.subscribe(channel: 'room-a', recovery: { epoch: 'e', offset: 3 })
    expect(result.fetch('offset')).to eq(5)
    expect(wait_for(deliveries)).to eq('recovered-4')
    expect(deliveries).to be_empty
    release.enqueue(true)

    expect(wait_for(deliveries)).to eq('recovered-5')
    expect(wait_for(deliveries)).to eq('live-b')
  end

  it 'continues dispatching command replies while recovered callbacks are blocked' do
    entered = Async::Queue.new
    release = Async::Queue.new
    protocol.on_publication('room-a') do |_event, _data, *, recovered:|
      entered.enqueue(recovered)
      release.dequeue
    end
    socket.on_write = method(:reply_to_command)

    protocol.subscribe(channel: 'room-a', recovery: { epoch: 'e', offset: 3 })
    expect(wait_for(entered)).to be(true)

    expect(protocol.presence(channel: 'presence:room')).to eq('ok' => true)
    release.enqueue(true)
  end

  it 'waits for callback capacity rather than discarding recovered publications' do
    values = Async::Queue.new
    release = Async::Queue.new
    protocol.on_publication('room-a') do |_event, data, *, **|
      values.enqueue(data.fetch('value'))
      release.dequeue if data.fetch('value') == 'recovered-4'
    end
    socket.on_write = ->(command) { socket.receive(recovery_reply(command, retained_publications)) }

    protocol.subscribe(channel: 'room-a', recovery: { epoch: 'e', offset: 3 })
    expect(wait_for(values)).to eq('recovered-4')
    expect(values).to be_empty
    release.enqueue(true)

    expect(wait_for(values)).to eq('recovered-5')
  end

  context 'with one producer queue slot' do
    let(:protocol_options) { { max_callback_queue: 1 } }

    it 'fails a recovery request when the bounded producer queue is saturated' do
      entered, release = fill_callback_capacity
      %w[one two three].each { |channel| protocol.on_publication(channel) { nil } }
      socket.on_write = lambda do |command|
        socket.receive(recovery_reply(command, [retained(4, command_channel(command))]))
      end
      dispatch_live('blocker', 1)
      entered.dequeue
      dispatch_live('blocker', 2)

      protocol.subscribe(channel: 'one', recovery: { epoch: 'e', offset: 3 })
      wait_until { producer_queue_empty? }
      protocol.subscribe(channel: 'two', recovery: { epoch: 'e', offset: 3 })

      expect do
        protocol.subscribe(channel: 'three', recovery: { epoch: 'e', offset: 3 })
      end.to raise_error(Volcano::Realtime::PendingLimitError)
      release.enqueue(true)
    end
  end

  it 'closes and notifies once when the reader fails' do
    errors = Async::Queue.new
    failures = Async::Queue.new
    protocol.instance_variable_set(:@events, protocol_events(errors, failures))
    broken = Object.new
    broken.define_singleton_method(:to_str) { raise IOError, 'reader failed' }

    socket.receive_raw(broken)
    expect(wait_for(errors).message).to eq('reader failed')
    expect(wait_for(failures).first.message).to eq('reader failed')

    expect(socket.close_count).to eq(1)
    expect([errors.empty?, failures.empty?]).to eq([true, true])
  end

  it 'closes from callback, producer, reader, and external tasks without self-wait' do
    expect(
      [close_from_callback, close_from_producer, close_from_reader, close_from_external_task]
    ).to eq([1, 1, 1, 1])
  end

  private

  def register_ordered_handler(channel, deliveries, release)
    protocol.on_publication(channel) do |_event, data, *, **|
      deliveries.enqueue(data.fetch('value'))
      release.dequeue if data.fetch('value') == 'recovered-4'
    end
  end

  def receive_recovery_and_live(command)
    socket.receive(
      recovery_reply(command, retained_publications),
      push('room-b', retained(6, 'live-b'))
    )
  end

  def reply_to_command(command)
    frame = if command.key?('subscribe')
              recovery_reply(command, retained_publications)
            else
              { 'id' => command.fetch('id'), 'result' => { 'ok' => true } }
            end
    socket.receive(frame)
  end

  def recovery_reply(command, publications)
    {
      'id' => command.fetch('id'),
      'result' => { 'recovered' => true, 'epoch' => 'e', 'offset' => 5, 'publications' => publications }
    }
  end

  def retained_publications
    [retained(4, 'recovered-4'), retained(5, 'recovered-5')]
  end

  def retained(offset, value)
    { 'epoch' => 'e', 'offset' => offset, 'data' => { 'event' => 'message', 'value' => value } }
  end

  def push(channel, publication) = { 'push' => { 'channel' => channel, 'pub' => publication } }

  def command_channel(command) = command.fetch('subscribe').fetch('channel')

  def fill_callback_capacity
    entered = Async::Queue.new
    release = Async::Queue.new
    protocol.on_publication('blocker') do
      entered.enqueue(true)
      release.dequeue
    end
    [entered, release]
  end

  def dispatch_live(channel, offset)
    protocol.__send__(:dispatch_publication, 'channel' => channel, 'pub' => retained(offset, 'blocker'))
  end

  def producer_queue_empty?
    protocol.instance_variable_get(:@publication_queue).empty?
  end

  def wait_until
    Async::Task.current.with_timeout(0.2) do
      Async::Task.current.yield until yield
    end
  end

  def protocol_events(errors, failures)
    RecoveryDispatchProtocol::Events.new(
      on_close: nil,
      on_error: ->(error) { errors.enqueue(error) },
      on_failure: ->(*args) { failures.enqueue(args) }
    )
  end

  def close_from_callback
    with_protocol do |candidate, candidate_socket|
      closed = Async::Queue.new
      candidate.on_publication('room') { candidate.close.then { closed.enqueue(true) } }
      candidate.__send__(:dispatch_publication, 'channel' => 'room', 'pub' => retained(1, 'live'))
      wait_for(closed)
      candidate_socket.close_count
    end
  end

  def close_from_producer
    with_protocol(max_callback_queue: 1) do |candidate, candidate_socket|
      queues = producer_close_queues
      prepare_producer_close(candidate, candidate_socket, queues)
      trigger_producer_close(candidate, queues)
      wait_until { candidate_socket.close_count == 1 }
      candidate_socket.close_count
    end
  end

  def producer_close_queues
    %i[blocker_entered blocker_release recovery_entered recovery_release].to_h do |name|
      [name, Async::Queue.new]
    end
  end

  def prepare_producer_close(candidate, candidate_socket, queues)
    register_producer_close_handlers(candidate, queues)
    candidate_socket.on_write = lambda do |command|
      candidate_socket.receive(recovery_reply(command, retained_publications))
    end
    dispatch_for(candidate, 'blocker', retained(1, 'first'))
    queues.fetch(:blocker_entered).dequeue
    dispatch_for(candidate, 'blocker', retained(2, 'queued'))
  end

  def trigger_producer_close(candidate, queues)
    candidate.subscribe(channel: 'recovery', recovery: { epoch: 'e', offset: 3 })
    dispatch_for(candidate, 'room', retained(6, 'live'))
    queues.fetch(:blocker_release).enqueue(true)
    queues.fetch(:recovery_entered).dequeue
  end

  def register_producer_close_handlers(candidate, queues)
    register_blocking_handler(candidate, queues)
    register_recovered_handler(candidate, queues)
    rejection = ->(*) { raise IOError, 'producer failed' }
    candidate.on_publication('room', on_rejection: rejection) { nil }
  end

  def register_blocking_handler(candidate, queues)
    candidate.on_publication('blocker') do |_event, data|
      next unless data.fetch('value') == 'first'

      queues.fetch(:blocker_entered).enqueue(true)
      queues.fetch(:blocker_release).dequeue
    end
  end

  def register_recovered_handler(candidate, queues)
    candidate.on_publication('recovery') do |_event, data|
      next unless data.fetch('value') == 'recovered-4'

      queues.fetch(:recovery_entered).enqueue(true)
      queues.fetch(:recovery_release).dequeue
    end
  end

  def dispatch_for(candidate, channel, publication)
    candidate.__send__(:dispatch_publication, 'channel' => channel, 'pub' => publication)
  end

  def close_from_reader
    with_protocol do |_candidate, candidate_socket|
      candidate_socket.finish
      wait_until { candidate_socket.close_count == 1 }
      candidate_socket.close_count
    end
  end

  def close_from_external_task
    with_protocol do |candidate, candidate_socket|
      candidate.close
      candidate_socket.close_count
    end
  end

  def with_protocol(**options)
    candidate_socket = RecoveryDispatchSocket.new
    candidate = RecoveryDispatchProtocol.new(socket: candidate_socket, task: Async::Task.current, **options)
    yield candidate, candidate_socket
  ensure
    candidate&.close
  end

  def wait_for(queue) = Async::Task.current.with_timeout(0.2) { queue.dequeue }
end
