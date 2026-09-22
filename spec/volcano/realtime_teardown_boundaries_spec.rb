# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:sockets) { [SpecSupport::FacadeSocket.new, SpecSupport::FacadeSocket.new] }
  let(:opened) { [] }
  let(:client) do
    Volcano::Client.new(
      anon_key: 'anon-key', access_token: 'access-token',
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: method(:open_socket), _realtime_reconnect_delay: ->(_attempt) { 0 }
    )
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  def open_socket(_address)
    socket = sockets.fetch(opened.length)
    opened << socket
    socket
  end

  it 'keeps inactive channels available when loss cleanup runs without a protocol' do
    channel = client.realtime.channel('room')

    client.realtime.__send__(:reset_after_protocol_loss)

    expect(client.realtime.channel('room')).to be(channel)
    expect(channel).not_to be_subscription_desired
    expect(client.realtime).not_to be_connected
    expect(opened).to be_empty
  end

  it 'rejects a recovery binding captured before the current session lineage' do
    _, lineage, = client.capture_session_binding
    client.auth.current_session = Volcano::Session.new(
      access_token: 'replacement', refresh_token: 'replacement-refresh', user_id: 'replacement-user'
    )
    channel = client.realtime.channel('room')
    channel.subscribe

    expect { channel.__send__(:validate_recovery_binding!, [lineage, {}]) }
      .to raise_error(Volcano::Error::SessionChangedError)
  end

  it 'allows a restored presence callback to disconnect from the reconnect task' do
    finished = Async::Queue.new
    channel = client.realtime.channel('room', type: :presence)
    disconnect_on_restoration(channel, finished)
    channel.subscribe

    sockets.first.fail_read(IOError.new('connection lost'))

    expect(Async::Task.current.with_timeout(1) { finished.dequeue }).to be(true)
    expect(opened.length).to eq(2)
    expect(opened).to all(be_closed)
    expect(client.realtime).not_to be_connected
  end

  private

  def disconnect_on_restoration(channel, finished)
    syncs = 0
    channel.on_presence_sync do
      syncs += 1
      next if syncs == 1

      client.realtime.disconnect
      finished.enqueue(true)
    end
  end
end
