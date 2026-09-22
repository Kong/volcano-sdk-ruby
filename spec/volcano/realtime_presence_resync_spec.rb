# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

PresenceResyncSignals = Data.define(:entered, :release, :received_ping, :resynced)

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:client) do
    Volcano::Client.new(
      anon_key: 'anon-key', access_token: 'access-token',
      _transport: SpecSupport::RealtimeAuthTransport.new, _realtime_socket_factory: ->(_address) { socket }
    )
  end
  let(:channel) { client.realtime.channel('lobby', type: :presence) }
  let(:signals) do
    PresenceResyncSignals.new(entered: Async::Queue.new, release: Async::Queue.new,
                              received_ping: Async::Queue.new, resynced: Async::Queue.new)
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  [nil, [], 'invalid'].each do |info|
    it "ignores non-object presence metadata at the state boundary: #{info.inspect}" do
      channel.subscribe
      previous = channel.presence_state

      channel.__send__(:presence_event, 'join', info, 1)

      expect(channel.presence_state).to equal(previous)
    end
  end

  it 'does not query presence for an obsolete subscription epoch' do
    channel.subscribe
    protocol = client.realtime.__send__(:protocol)
    previous_commands = socket.commands.dup

    channel.__send__(:sync_presence, protocol, 0)

    expect(socket.commands).to eq(previous_commands)
    expect(channel.presence_state).to be_empty
  end

  it 'requests an authoritative presence snapshot after callback overflow' do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    socket.on_write = method(:respond)
    register_callbacks
    channel.subscribe
    publish_join('blocked')
    wait_for(signals.entered)
    publish_join('queued')
    publish_join('overflow')
    socket.receive_raw('{}')
    wait_for(signals.received_ping)
    signals.release.enqueue(true)

    expect(wait_for(signals.resynced).keys).to eq(['resynced'])
    expect(socket.commands.count { |command| command.key?('presence') }).to eq(2)
    expect(channel.presence_state.keys).to eq(['resynced'])
  end

  private

  def register_callbacks
    channel.on('join') do |info|
      next unless info.client == 'blocked'

      signals.entered.enqueue(true)
      signals.release.dequeue
    end
    channel.on_presence_sync { |state| signals.resynced.enqueue(state) if state.key?('resynced') }
  end

  def respond(command)
    if command.empty?
      signals.received_ping.enqueue(true)
      return :defer
    end
    return unless command.key?('presence')

    count = socket.commands.count { |frame| frame.key?('presence') }
    state = count == 1 ? {} : { 'resynced' => { 'client' => 'resynced' } }
    socket.respond(command.fetch('id'), result: { 'presence' => state })
    :defer
  end

  def publish_join(id)
    socket.presence_event(channel: channel.name, event: 'join', info: { 'client' => id })
  end

  def wait_for(queue) = Async::Task.current.with_timeout(1) { queue.dequeue }
end
