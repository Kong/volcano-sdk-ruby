# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:addresses) { [] }
  let(:access_token) { 'access-token' }
  let(:api_url) { 'https://api.example.test' }
  let(:client) do
    Volcano::Client.new(
      anon_key: 'anon key', access_token: access_token, api_url: api_url,
      _transport: SpecSupport::RealtimeAuthTransport.new,
      _realtime_socket_factory: method(:open_socket)
    )
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  def open_socket(address)
    addresses << address
    socket
  end

  {
    'http://localhost:8080/api/' => 'ws://localhost:8080/api/realtime/v1/websocket?apikey=anon%20key',
    'https://api.example.test/' => 'wss://api.example.test/realtime/v1/websocket?apikey=anon%20key'
  }.each do |endpoint, address|
    context "with API endpoint #{endpoint}" do
      let(:api_url) { endpoint }

      it 'uses the corresponding WebSocket scheme and escapes the anonymous key' do
        client.realtime.channel('room').subscribe

        expect(addresses).to eq([address])
        expect(socket.commands.first).to eq('id' => 1, 'connect' => { 'token' => access_token })
      end
    end
  end

  context 'without an active session' do
    let(:access_token) { nil }

    it 'reports the authentication failure before opening a socket' do
      errors = Async::Queue.new
      client.realtime.on_error { |context| errors.enqueue(context) }

      expect { client.realtime.channel('room').subscribe }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      error = Async::Task.current.with_timeout(1) { errors.dequeue }

      expect(error.message).to eq('No active session')
      expect(error.error).to be_a(Volcano::Error::AuthenticationError)
      expect(addresses).to be_empty
      expect(socket.commands).to be_empty
    end
  end

  it 'clears a selected database when assigned nil' do
    client.realtime.database_name = 'app'
    client.realtime.database_name = nil

    expect(client.realtime.database_name).to be_nil
    expect(addresses).to be_empty
  end
end
