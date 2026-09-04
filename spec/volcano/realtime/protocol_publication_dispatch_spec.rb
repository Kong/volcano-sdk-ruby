# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'spec_helper'

PublicationDispatchProtocol = Volcano::Realtime.const_get(:Protocol, false)
ProtocolPublicationDispatch = Volcano::Realtime.const_get(:ProtocolPublicationDispatch, false)

class PublicationDispatchSocket
  attr_reader :close_count

  def initialize
    @incoming = Async::Queue.new
    @close_count = 0
  end

  def read = @incoming.dequeue

  def close
    @close_count += 1
    @incoming.enqueue(nil)
  end
end

RSpec.describe ProtocolPublicationDispatch do
  around do |example|
    Async { example.run }.wait
  end

  let(:socket) { PublicationDispatchSocket.new }
  let(:protocol) do
    PublicationDispatchProtocol.new(socket: socket, task: Async::Task.current, max_callback_queue: 1)
  end

  after { protocol.close }

  it 'delivers valid live publications with transport metadata' do
    deliveries = Async::Queue.new
    protocol.on_publication('broadcast:room') do |event, data, publication, recovered:|
      deliveries.enqueue([event, data, publication, recovered])
    end
    publication = publication(offset: 4, value: 'live')

    dispatch('project:broadcast:room', publication)

    event, data, metadata, recovered = wait_for(deliveries)
    expect([event, data, recovered]).to eq(['message', publication.fetch('data'), false])
    expect(metadata).to eq(publication)
  end

  it 'records malformed publications and non-hash data as dropped' do
    set_position('broadcast:room', 3)
    protocol.on_publication('broadcast:room') { raise 'must not run' }

    dispatch('broadcast:room', 'not-a-publication')
    dispatch('broadcast:room', { 'epoch' => 'e', 'offset' => 4, 'data' => [] })
    complete('broadcast:room', 4)

    expect(position('broadcast:room')).to eq(epoch: 'e', offset: 3)
  end

  it 'records a valid publication without a matching handler as dropped' do
    set_position('broadcast:room', 3)

    dispatch('project:broadcast:room', publication(offset: 4))
    complete('broadcast:room', 4)

    expect(position('broadcast:room')).to eq(epoch: 'e', offset: 3)
  end

  it 'uses only the longest matching handler or recovery channel' do
    deliveries = Async::Queue.new
    protocol.on_publication('room') { |_event, data| deliveries.enqueue([:short, data['value']]) }
    long = protocol.on_publication('broadcast:room') do |_event, data|
      deliveries.enqueue([:long, data['value']])
    end

    dispatch('project:broadcast:room', publication(offset: 4))

    expect(wait_for(deliveries)).to eq([:long, nil])
    protocol.off_publication('broadcast:room', long)
    set_position('broadcast:room', 3)
    dispatch('project:broadcast:room', publication(offset: 4, value: 'dropped'))
    dispatch('room', publication(offset: 1, value: 'sentinel'))
    expect(wait_for(deliveries)).to eq([:short, 'sentinel'])
    expect(position('broadcast:room')).to eq(epoch: 'e', offset: 3)
  end

  it 'delivers to the handler snapshot captured at admission' do
    entered = Async::Queue.new
    release = Async::Queue.new
    delivered = Async::Queue.new
    protocol.on_publication('broadcast:blocker') do
      entered.enqueue(true)
      release.dequeue
    end
    handler = protocol.on_publication('broadcast:room') { delivered.enqueue(true) }
    dispatch('broadcast:blocker', publication(offset: 1))
    entered.dequeue

    dispatch('broadcast:room', publication(offset: 4))
    protocol.off_publication('broadcast:room', handler)
    release.enqueue(true)

    expect(wait_for(delivered)).to be(true)
  end

  it 'bounds live callback work and invokes the captured rejection hook' do
    entered, release = block_callbacks
    rejected = Async::Queue.new
    protocol.on_publication('broadcast:room', on_rejection: ->(pub) { rejected.enqueue(pub) }) { nil }
    dispatch('broadcast:blocker', publication(offset: 1))
    entered.dequeue
    dispatch('broadcast:blocker', publication(offset: 2))

    dropped = publication(offset: 4, value: 'dropped')
    dispatch('broadcast:room', dropped)

    expect(wait_for(rejected)).to eq(dropped)
    release.enqueue(true)
  end

  it 'removes a rejection hook with its publication handler' do
    entered, release = block_callbacks
    rejected = Async::Queue.new
    handler = protocol.on_publication('broadcast:room', on_rejection: ->(*) { rejected.enqueue(true) }) { nil }
    protocol.off_publication('broadcast:room', handler)
    set_position('broadcast:room', 3)
    dispatch('broadcast:blocker', publication(offset: 1))
    entered.dequeue
    dispatch('broadcast:blocker', publication(offset: 2))

    dispatch('broadcast:room', publication(offset: 4))
    complete('broadcast:room', 4)

    expect(rejected).to be_empty
    expect(position('broadcast:room')).to eq(epoch: 'e', offset: 3)
    release.enqueue(true)
  end

  it 'isolates callback exceptions from later publication delivery' do
    delivered = Async::Queue.new
    failed = Async::Queue.new
    protocol.on_publication('broadcast:room') do |_event, data|
      if data.fetch('value') == 'bad'
        failed.enqueue(true)
        raise 'callback failed'
      end

      delivered.enqueue(data.fetch('value'))
    end

    dispatch('broadcast:room', publication(offset: 1, value: 'bad'))
    wait_for(failed)
    dispatch('broadcast:room', publication(offset: 2, value: 'good'))

    expect(wait_for(delivered)).to eq('good')
    expect(socket.close_count).to eq(0)
  end

  private

  def block_callbacks
    entered = Async::Queue.new
    release = Async::Queue.new
    protocol.on_publication('broadcast:blocker') do
      entered.enqueue(true)
      release.dequeue
    end
    [entered, release]
  end

  def dispatch(channel, pub)
    protocol.__send__(:dispatch_publication, 'channel' => channel, 'pub' => pub)
  end

  def publication(offset:, value: nil)
    { 'epoch' => 'e', 'offset' => offset, 'data' => { 'event' => 'message', 'value' => value } }
  end

  def set_position(channel, offset)
    protocol.__send__(:set_recovery_position, channel, 'e', offset)
  end

  def complete(channel, offset)
    protocol.__send__(:complete_publication, channel, { 'epoch' => 'e', 'offset' => offset })
  end

  def position(channel) = protocol.__send__(:position, channel)

  def wait_for(queue) = Async::Task.current.with_timeout(0.2) { queue.dequeue }
end
