# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:client) do
    instance = Volcano::Client.new(
      anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: ->(_address) { socket }
    )
    instance.auth.sign_in(email: 'user@example.com', password: 'secret')
    instance
  end
  let(:channel) { client.realtime.channel('lobby', type: :presence) }

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  [nil, 'invalid', [], false].each do |connection_info|
    it "defaults missing user and invalid connection metadata: #{connection_info.inspect}" do
      socket.on_write = lambda do |command|
        next unless command.key?('presence')

        snapshot = { 'fallback-client' => { 'conn_info' => connection_info } }
        socket.respond(command.fetch('id'), result: { 'presence' => snapshot })
        :defer
      end

      channel.subscribe

      expect(channel.presence_state).to eq(
        'fallback-client' => described_class::PresenceInfo.new(client: 'fallback-client')
      )
      expect(channel.presence_state.fetch('fallback-client').data).to be_frozen
    end
  end

  def defer_presence
    pending = Async::Queue.new
    socket.on_write = lambda do |command|
      next unless command.key?('presence')

      pending.enqueue(command)
      :defer
    end
    pending
  end

  def unsubscribe_before_reply(command)
    task = Async::Task.current
    unsubscribing = task.async { channel.unsubscribe }
    task.with_timeout(1) { task.yield while channel.subscription_desired? }
    socket.respond(command.fetch('id'), result: { 'presence' => { 'stale-client' => {} } })
    task.with_timeout(1) { unsubscribing.wait }
  end

  it 'discards an in-flight presence snapshot and queued join after unsubscribe' do
    pending = defer_presence
    states = []
    joins = []
    channel.on_presence_sync { |state| states << state }
    channel.on('join') { |info| joins << info }
    subscribing = Async::Task.current.async { channel.subscribe }
    command = wait_for(pending)
    socket.presence_event(channel: channel.name, event: 'join', info: { 'client' => 'stale-join' })

    unsubscribe_before_reply(command)
    Async::Task.current.with_timeout(1) { subscribing.wait }
    finish_delivery

    expect(channel.presence_state).to be_empty
    expect(states).to eq([{}])
    expect(joins).to be_empty
  end

  private

  def finish_delivery
    finished = Async::Queue.new
    sentinel = client.realtime.channel('sentinel').on('message') { finished.enqueue(true) }
    sentinel.subscribe
    socket.publication(channel: sentinel.name, data: { 'event' => 'message' })
    expect(wait_for(finished)).to be(true)
  end

  def wait_for(queue) = Async::Task.current.with_timeout(1) { queue.dequeue }
end
