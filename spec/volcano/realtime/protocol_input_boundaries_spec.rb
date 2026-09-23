# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'spec_helper'
require 'support/protocol_socket'

ProtocolInputBoundaries = Volcano::Realtime.const_get(:Protocol, false)

RSpec.describe ProtocolInputBoundaries do
  around { |example| Async { example.run }.wait }

  let(:socket) { SpecSupport::ProtocolSocket.new }
  let(:protocol) { described_class.new(socket: socket, task: Async::Task.current) }

  after { protocol.close }

  [" \t\n", JSON.generate('unknown' => {}), JSON.generate('id' => 'invalid'),
   JSON.generate('push' => { 'unknown' => {} })].each do |frame|
    it "continues receiving after an ignored frame #{frame.inspect}" do
      delivered = Async::Queue.new
      protocol.on_presence('presence:room') { |event, info| delivered.enqueue([event, info]) }

      socket.receive(frame, presence_push)

      expect(wait_for(delivered)).to eq(['join', { 'client' => 'client-1' }])
      expect(socket).not_to be_closed
      expect(socket.writes).to be_empty
    end
  end

  it 'closes a connection after a non-object push' do
    socket.receive(JSON.generate('push' => 'malformed'))

    Async::Task.current.with_timeout(1) { protocol.instance_variable_get(:@reader_task).wait }

    expect(socket).to be_closed
  end

  it 'rejects a malformed command error before exposing it to a caller' do
    expect do
      protocol.__send__(:reply_value, { 'error' => 'malformed' }, 'presence')
    end.to raise_error(TypeError, 'realtime error must be an object')
  end

  it 'preserves a missing backtrace while wrapping a socket error' do
    error = protocol.__send__(:closed_error, IOError.new('socket closed'))

    expect(error).to be_a(Volcano::Realtime::ClosedError)
    expect(error.message).to eq('socket closed')
    expect(error.backtrace).to be_nil
  end

  it 'keeps the remaining presence handler when another is removed' do
    delivered = Async::Queue.new
    removed = protocol.on_presence('presence:room') { delivered.enqueue(:removed) }
    protocol.on_presence('presence:room') { delivered.enqueue(:retained) }
    protocol.off_presence('presence:room', removed)

    socket.receive(presence_push)

    expect(wait_for(delivered)).to eq(:retained)
    expect(delivered).to be_empty
  end

  it 'keeps the remaining publication handler when another is removed' do
    delivered = Async::Queue.new
    removed = protocol.on_publication('broadcast:room') { delivered.enqueue(:removed) }
    protocol.on_publication('broadcast:room') { delivered.enqueue(:retained) }
    protocol.off_publication('broadcast:room', removed)

    socket.receive(JSON.generate('push' => { 'channel' => 'broadcast:room', 'pub' => { 'data' => {} } }))

    expect(wait_for(delivered)).to eq(:retained)
    expect(delivered).to be_empty
  end

  it 'stops later presence callbacks when a handler closes the protocol' do
    events = []
    closed = Async::Queue.new
    protocol.on_presence('presence:room') do
      protocol.close
      closed.enqueue(true)
    end
    protocol.on_presence('presence:room') { events << :late }
    socket.receive(presence_push)

    expect(wait_for(closed)).to be(true)
    Async::Task.current.with_timeout(1) { Async::Task.current.children.each(&:wait) }
    expect(events).to be_empty
    expect(socket).to be_closed
  end

  it 'rejects misspelled limits before starting protocol tasks' do
    expect { described_class.new(socket: socket, task: Async::Task.current, max_pendig: 1) }
      .to raise_error(ArgumentError, 'unknown keyword: max_pendig')
    expect(socket.writes).to be_empty
    expect(Async::Task.current.children).to be_nil
  end

  it 'does not send an unsubscribe for a channel without a subscription' do
    expect(protocol.unsubscribe(channel: 'broadcast:missing')).to eq({})
    expect(socket.writes).to be_empty
  end

  private

  def presence_push
    JSON.generate('push' => { 'channel' => 'presence:room', 'join' => { 'info' => { 'client' => 'client-1' } } })
  end

  def wait_for(queue) = Async::Task.current.with_timeout(1) { queue.dequeue }
end
