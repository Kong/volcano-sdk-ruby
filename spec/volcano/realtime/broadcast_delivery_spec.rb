# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'spec_helper'

BroadcastDeliveryChannel = Volcano::Realtime.const_get(:Channel, false)
BroadcastDeliveryBatchConfig = Volcano::Realtime.const_get(:PostgresBatchConfig, false)
BroadcastPositionLedger = Volcano::Realtime.const_get(:ProtocolRecoveryPosition, false)
BroadcastDelivery = Volcano::Realtime.const_get(:BroadcastDelivery, false)

class BroadcastDeliveryProtocol
  include BroadcastPositionLedger

  Registration = Data.define(:channel, :handler, :rejection)

  attr_reader :registrations

  def initialize
    initialize_recovery_positions
    @registrations = []
    @connected = true
  end

  def on_publication(channel, on_rejection: nil, &handler)
    @registrations << Registration.new(channel:, handler:, rejection: on_rejection)
    handler
  end

  def off_publication(channel, handler)
    @registrations.reject! { |entry| entry.channel == channel && entry.handler.equal?(handler) }
    nil
  end

  def subscribe(**) = {}
  def unsubscribe(**) = {}
  def connected? = @connected
end

class BroadcastProtocolProvider
  attr_accessor :current

  def initialize(current)
    @current = current
  end

  def call = current
end

class BroadcastDeliveryRealtime
  def ensure_open! = self
end

RSpec.describe BroadcastDelivery do
  around do |example|
    Async { example.run }.wait
  end

  let(:protocol) { BroadcastDeliveryProtocol.new }
  let(:provider) { BroadcastProtocolProvider.new(protocol) }
  let(:channel) { build_channel(provider) }
  let(:messages) { Async::Queue.new }

  it 'delivers one immutable message payload and completes its publication' do
    channel.on('message', ->(message) { messages.enqueue(message) })
    channel.subscribe
    set_position(protocol, 3)
    data = { 'event' => 'message', 'nested' => { 'value' => 'live' } }

    deliver(current_registration(protocol), data:, publication: publication(4, data:))

    expect(messages.size).to eq(1)
    message = messages.dequeue
    expect(message).to eq(data)
    expect([message.frozen?, message.fetch('nested').frozen?]).to eq([true, true])
    expect(position(protocol)).to eq(epoch: 'e', offset: 4)
  end

  it 'drops unsupported events without invoking message callbacks' do
    subscribe_with_message_listener
    registration = current_registration(protocol)
    unsupported = publication(4, data: { 'event' => 'unsupported' })
    deliver(registration, publication: unsupported, event: 'unsupported')

    expect_publication_dropped
  end

  it 'drops malformed message data without invoking callbacks' do
    subscribe_with_message_listener
    deliver(current_registration(protocol), publication: publication(4), data: ['malformed'])

    expect_publication_dropped
  end

  it 'drops messages that have no listener' do
    channel.subscribe
    set_position(protocol, 3)

    deliver(current_registration(protocol), publication: publication(4))
    complete(protocol, 4)

    expect(messages).to be_empty
    expect(position(protocol)).to eq(epoch: 'e', offset: 3)
  end

  it 'ignores a delivery queued before unsubscribe' do
    channel.on('message') { |message| messages.enqueue(message) }
    channel.subscribe
    set_position(protocol, 3)
    old_registration = current_registration(protocol)
    queued = queue_behind_callback_lock(old_registration, publication(4))

    channel.unsubscribe
    release_queued(queued)

    expect(messages).to be_empty
    expect(position(protocol)).to eq(epoch: 'e', offset: 3)
  end

  it 'isolates removed channels from replacements using the same protocol' do
    channel.on('message') { |message| messages.enqueue(message) }
    channel.subscribe
    set_position(protocol, 3)
    queued = queue_behind_callback_lock(current_registration(protocol), publication(11))

    channel.__send__(:remove)
    replacement = build_channel(provider)
    replacement.on('message') { |message| messages.enqueue(message) }
    replacement.subscribe
    set_position(protocol, 10)
    release_queued(queued)
    deliver(current_registration(protocol), publication: publication(11, value: 'new'))

    expect(messages.dequeue.fetch('value')).to eq('new')
    expect(messages).to be_empty
    expect(position(protocol)).to eq(epoch: 'e', offset: 11)
  end

  it 'delivers only the current registration after immediate resubscribe' do
    channel.on('message') { |message| messages.enqueue(message.fetch('value')) }
    channel.subscribe
    set_position(protocol, 3)
    queued = queue_behind_callback_lock(current_registration(protocol), publication(4, value: 'old'))

    channel.unsubscribe
    channel.subscribe
    release_queued(queued)
    deliver(current_registration(protocol), publication: publication(4, value: 'new'))

    expect(messages.dequeue).to eq('new')
    expect(messages).to be_empty
    expect(position(protocol)).to eq(epoch: 'e', offset: 4)
  end

  it 'ignores delayed rejection from an old generation' do
    channel.on('message') { |message| messages.enqueue(message.fetch('value')) }
    channel.subscribe
    old_registration = current_registration(protocol)
    channel.unsubscribe
    channel.subscribe
    set_position(protocol, 3)

    old_registration.rejection.call(publication(4, value: 'old'))
    deliver(current_registration(protocol), publication: publication(4, value: 'new'))

    expect(messages.dequeue).to eq('new')
    expect(position(protocol)).to eq(epoch: 'e', offset: 4)
  end

  it 'records rejection from the current generation' do
    channel.on('message') { |message| messages.enqueue(message) }
    channel.subscribe
    set_position(protocol, 3)

    current_registration(protocol).rejection.call(publication(4))
    deliver(current_registration(protocol), publication: publication(5))

    expect(position(protocol)).to eq(epoch: 'e', offset: 3)
  end

  it 'allows a message callback to unsubscribe its channel' do
    channel.on('message') do |message|
      channel.unsubscribe
      messages.enqueue(message.fetch('value'))
    end
    channel.subscribe
    set_position(protocol, 3)

    deliver(current_registration(protocol), publication: publication(4, value: 'last'))

    expect(messages.dequeue).to eq('last')
    expect(position(protocol)).to eq(epoch: 'e', offset: 4)
  end

  it 'ignores queued delivery from a lost protocol after restoration' do
    replacement_protocol = BroadcastDeliveryProtocol.new
    channel.on('message') { |message| messages.enqueue(message) }
    channel.subscribe
    queued = queue_behind_callback_lock(current_registration(protocol), publication(4))

    channel.protocol_lost(protocol)
    provider.current = replacement_protocol
    channel.restore_subscription(replacement_protocol)
    set_position(replacement_protocol, 9)
    release_queued(queued)

    expect(messages).to be_empty
    expect(position(replacement_protocol)).to eq(epoch: 'e', offset: 9)
  end

  it 'clears broadcast recovery state when the channel is removed' do
    channel.subscribe
    set_position(protocol, 3)

    channel.__send__(:remove)

    expect(position(protocol)).to be_nil
  end

  private

  def build_channel(protocol_provider)
    BroadcastDeliveryChannel.new(
      BroadcastDeliveryRealtime.new, protocol_provider, 'broadcast:room', :broadcast,
      batch_config: BroadcastDeliveryBatchConfig.new(auto_fetch: true, batch_window_ms: 20, max_batch_size: 50)
    )
  end

  def current_registration(candidate)
    candidate.registrations.last || raise('publication handler not registered')
  end

  def deliver(registration, publication:, event: 'message', data: nil, recovered: false)
    payload = data || publication.fetch('data')
    registration.handler.call(event, payload, publication, recovered: recovered)
  end

  def subscribe_with_message_listener
    channel.on('message') { |message| messages.enqueue(message) }
    channel.subscribe
    set_position(protocol, 3)
  end

  def expect_publication_dropped
    complete(protocol, 4)
    expect(messages).to be_empty
    expect(position(protocol)).to eq(epoch: 'e', offset: 3)
  end

  def queue_behind_callback_lock(registration, publication)
    entered, release, holder = hold_callback_lock
    entered.dequeue
    delivery = Async::Task.current.async { deliver(registration, publication:) }
    Async::Task.current.yield
    [release, delivery, holder]
  end

  def hold_callback_lock
    entered = Async::Queue.new
    release = Async::Queue.new
    holder = Async::Task.current.async do
      channel.__send__(:callback_lock).acquire do
        entered.enqueue(true)
        release.dequeue
      end
    end
    [entered, release, holder]
  end

  def release_queued(queued)
    release, delivery, holder = queued
    release.enqueue(true)
    holder.wait
    delivery.wait
  end

  def set_position(candidate, offset)
    candidate.__send__(:set_recovery_position, 'broadcast:room', 'e', offset)
  end

  def complete(candidate, offset)
    candidate.__send__(:complete_publication, 'broadcast:room', publication(offset))
  end

  def position(candidate) = candidate.__send__(:position, 'broadcast:room')

  def publication(offset, value: nil, data: nil)
    payload = data || { 'event' => 'message', 'value' => value }
    { 'epoch' => 'e', 'offset' => offset, 'data' => payload }
  end
end
