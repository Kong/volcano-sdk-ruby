# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'async/http/endpoint'
require 'async/websocket/client'

RSpec.describe Volcano::Realtime do
  let(:client) do
    Volcano::Client.new(anon_key: 'anon key', access_token: 'access-token', api_url: 'https://api.test/base')
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  it 'opens the default WebSocket endpoint and redacts connection failures' do
    addresses = []
    allow(Async::WebSocket::Client).to receive(:connect) do |endpoint|
      addresses << endpoint.to_url.to_s
      raise IOError, 'connection refused for access-token'
    end

    expect { client.realtime.channel('room').subscribe }.to raise_error(Volcano::Error::TransportError) do |error|
      expect(error.message).not_to include('access-token')
    end
    expect(addresses).to eq(['wss://api.test/base/realtime/v1/websocket?apikey=anon%20key'])
  end

  it 'delivers later error callbacks when an earlier callback raises' do
    errors = Async::Queue.new
    allow(Async::WebSocket::Client).to receive(:connect).and_raise(IOError, 'connection refused')
    client.realtime.on_error { raise 'subscriber failed' }
    client.realtime.on_error { |context| errors.enqueue(context) }

    expect { client.realtime.channel('room').subscribe }.to raise_error(Volcano::Error::TransportError)
    context = Async::Task.current.with_timeout(1) { errors.dequeue }
    expect(context.message).to eq('connection refused')
    expect(context.error).to be_a(Volcano::Error::TransportError)
  end

  it 'preserves session replacement failure when closing the rejected socket also fails' do
    socket = instance_double(IO)
    allow(socket).to receive(:close).and_raise(IOError, 'close failed')
    allow(Async::WebSocket::Client).to receive(:connect) do
      client.auth.current_session = Volcano::Session.new(
        access_token: 'replacement', refresh_token: 'refresh', user_id: 'user'
      )
      socket
    end

    expect { client.realtime.channel('room').subscribe }.to raise_error(Volcano::Error::SessionChangedError)
    expect(socket).to have_received(:close)
    expect(client.realtime).not_to be_connected
  end

  %i[broadcast postgres].each do |type|
    it "rejects presence tracking on a #{type} channel before connection" do
      channel = client.realtime.channel('room', type: type)
      expect { channel.track({}) }.to raise_error(ArgumentError, 'operation is only available for presence channels')
    end

    it "rejects presence synchronization callbacks on a #{type} channel" do
      channel = client.realtime.channel('room', type: type)
      expect { channel.on_presence_sync { nil } }
        .to raise_error(ArgumentError, 'operation is only available for presence channels')
    end
  end
end
