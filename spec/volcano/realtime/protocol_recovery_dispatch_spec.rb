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

    it 'keeps dispatching replies while a live rejection hook waits' do
      hook_entered = Async::Queue.new
      hook_release = Async::Queue.new
      entered, release = fill_callback_capacity
      register_blocking_rejection('room', hook_entered, hook_release)
      socket.on_write = method(:reply_ok)
      fill_live_callback_queue(entered)

      socket.receive(push('room', retained(3, 'rejected')))
      hook_entered.dequeue
      command = Async::Task.current.async { protocol.presence(channel: 'presence:room') }

      expect(wait_task(command)).to eq('ok' => true)
    ensure
      hook_release&.enqueue(true)
      release&.enqueue(true)
    end

    it 'fails a recovery request when the bounded producer queue is saturated' do
      hook_entered = Async::Queue.new
      hook_release = Async::Queue.new
      release = saturate_producer(hook_entered, hook_release)
      failed = failed_recovery_task
      2.times { release.enqueue(true) }
      hook_entered.dequeue

      result = Async::Task.current.with_timeout(0.2) { protocol.presence(channel: 'presence:room') }
      expect(result).to eq('ok' => true)
      hook_release.enqueue(true)
      expect(wait_task(failed)).to be_a(Volcano::Realtime::PendingLimitError)
    ensure
      hook_release&.enqueue(true)
      release&.enqueue(true)
    end

    it 'coalesces overflow by the captured multi-hook registration snapshot' do
      queues = multi_hook_queues
      prepare_multi_hook_overflow(queues)

      (1..20).each { |offset| dispatch_live('target', offset) }

      expect(protocol.instance_variable_get(:@publication_queue).size).to eq(2)
      drain_blocking_callbacks(queues)
      queues.fetch(:gate_release).enqueue(true)
      publications = [wait_for(queues.fetch(:first_hook)), wait_for(queues.fetch(:second_hook))]
      expect(publications.map { |publication| publication.fetch('offset') }).to eq([2, 2])
      expect([queues.fetch(:first_hook).empty?, queues.fetch(:second_hook).empty?]).to eq([true, true])
    ensure
      queues&.fetch(:gate_release)&.enqueue(true)
      2.times { queues&.fetch(:callback_release)&.enqueue(true) }
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

  def reply_ok(command)
    socket.receive('id' => command.fetch('id'), 'result' => { 'ok' => true })
  end

  def reply_saturation_command(command)
    return reply_ok(command) unless command.key?('subscribe')

    socket.receive(recovery_reply(command, [retained(4, command_channel(command))]))
  end

  def saturate_producer(hook_entered, hook_release)
    entered, release = fill_callback_capacity
    %w[one two].each { |channel| protocol.on_publication(channel) { nil } }
    register_blocking_rejection('three', hook_entered, hook_release)
    socket.on_write = method(:reply_saturation_command)
    fill_live_callback_queue(entered)
    protocol.subscribe(channel: 'one', recovery: { epoch: 'e', offset: 3 })
    wait_until { producer_queue_empty? }
    protocol.subscribe(channel: 'two', recovery: { epoch: 'e', offset: 3 })
    release
  end

  def failed_recovery_task
    Async::Task.current.async do
      protocol.subscribe(channel: 'three', recovery: { epoch: 'e', offset: 3 })
    rescue StandardError => e
      e
    end
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

  def fill_live_callback_queue(entered)
    dispatch_live('blocker', 1)
    entered.dequeue
    dispatch_live('blocker', 2)
  end

  def register_blocking_rejection(channel, entered, release)
    rejection = lambda do |_publication|
      entered.enqueue(true)
      release.dequeue
    end
    protocol.on_publication(channel, on_rejection: rejection) { nil }
  end

  def multi_hook_queues
    names = %i[
      callback_entered callback_release callback_drained gate_entered gate_release first_hook second_hook
    ]
    names.to_h do |name|
      [name, Async::Queue.new]
    end
  end

  def prepare_multi_hook_overflow(queues)
    register_callback_gate(queues)
    register_blocking_rejection('gate', queues.fetch(:gate_entered), queues.fetch(:gate_release))
    register_target_rejections(queues)
    block_publication_producer(queues)
  end

  def register_target_rejections(queues)
    protocol.on_publication('target', on_rejection: ->(pub) { queues.fetch(:first_hook).enqueue(pub) }) { nil }
    protocol.on_publication('target', on_rejection: ->(pub) { queues.fetch(:second_hook).enqueue(pub) }) { nil }
  end

  def block_publication_producer(queues)
    dispatch_live('blocker', 1)
    queues.fetch(:callback_entered).dequeue
    dispatch_live('blocker', 2)
    dispatch_live('gate', 1)
    queues.fetch(:gate_entered).dequeue
  end

  def register_callback_gate(queues)
    protocol.on_publication('blocker') do |_event, _data, publication|
      queues.fetch(:callback_entered).enqueue(publication.fetch('offset'))
      queues.fetch(:callback_release).dequeue
      queues.fetch(:callback_drained).enqueue(publication.fetch('offset'))
    end
  end

  def drain_blocking_callbacks(queues)
    2.times { queues.fetch(:callback_release).enqueue(true) }
    2.times { queues.fetch(:callback_drained).dequeue }
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

  def wait_task(task) = Async::Task.current.with_timeout(0.2) { task.wait }
end
