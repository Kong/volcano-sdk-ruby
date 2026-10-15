# frozen_string_literal: true

require 'async'
require 'protocol/websocket/error'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:client) do
    Volcano::Client.new(
      anon_key: 'anon', access_token: 'access-token',
      _realtime_socket_factory: ->(_address) { socket }
    )
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  it 'preserves a WebSocket disconnect code and reason during startup' do
    socket.on_write = lambda do |_command|
      socket.fail_read(Protocol::WebSocket::ClosedError.new('permission denied', 3507))
      :defer
    end
    expect { client.realtime.channel('room').subscribe }
      .to raise_error(described_class::ClosedError) { |error|
            expect(error).to have_attributes(message: 'permission denied', code: 3507)
          }
    expect(socket).to be_closed
    expect(client.realtime).not_to be_connected
  end

  it 'rejects pending startup immediately on a disconnect push' do
    socket.on_write = lambda do |_command|
      socket.receive_raw(JSON.generate('push' => { 'disconnect' => { 'code' => 3507,
                                                                     'reason' => 'permission denied' } }))
      :defer
    end
    expect { Async::Task.current.with_timeout(0.2) { client.realtime.channel('room').subscribe } }
      .to raise_error(described_class::ClosedError) { |error|
            expect(error).to have_attributes(message: 'permission denied', code: 3507)
          }
    expect(socket).to be_closed
  end

  it 'uses a fallback reason when a disconnect push omits valid metadata' do
    socket.on_write = lambda do |_command|
      socket.receive_raw(JSON.generate('push' => { 'disconnect' => { 'code' => '3507', 'reason' => '' } }))
      :defer
    end
    expect { client.realtime.channel('room').subscribe }
      .to raise_error(described_class::ClosedError) { |error|
            expect(error).to have_attributes(message: 'realtime connection closed', code: nil)
          }
    expect(socket).to be_closed
  end

  it 'rejects a malformed disconnect push and closes its transport' do
    socket.on_write = lambda do |_command|
      socket.receive_raw(JSON.generate('push' => { 'disconnect' => nil }))
      :defer
    end
    expect { client.realtime.channel('room').subscribe }
      .to raise_error(described_class::ClosedError, 'realtime disconnect must be an object')
    expect(socket).to be_closed
  end
end
