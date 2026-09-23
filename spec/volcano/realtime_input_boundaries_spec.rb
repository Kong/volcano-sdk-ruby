# frozen_string_literal: true

require 'spec_helper'
require 'support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:realtime) do
    Volcano::Client.new(
      anon_key: 'anon-key', _transport: SpecSupport::RealtimeAuthTransport.new
    ).realtime
  end

  it 'rejects a non-object connect response before activating the protocol' do
    protocol_class = described_class.const_get(:Protocol, false)
    protocol = instance_double(protocol_class)
    allow(protocol).to receive(:connect).and_return([])

    expect do
      realtime.__send__(:checked_connect_result, protocol, 'access-token')
    end.to raise_error(TypeError, 'realtime connect result must be an object')
    expect(protocol).to have_received(:connect).with(token: 'access-token')
  end

  it 'preserves a network error backtrace while mapping it to a transport error' do
    failure = IOError.new('socket failed')
    failure.set_backtrace(['socket.rb:12'])

    error = realtime.__send__(:public_error, failure)

    expect(error).to be_a(Volcano::Error::TransportError)
    expect(error.message).to eq('socket failed')
    expect(error.backtrace).to eq(['socket.rb:12'])
  end

  it 'maps a network error without inventing a backtrace' do
    error = realtime.__send__(:public_error, IOError.new('socket failed'))

    expect(error).to be_a(Volcano::Error::TransportError)
    expect(error.backtrace).to be_nil
  end

  it 'rejects a non-array Postgres row lookup result' do
    expect do
      realtime.__send__(:validate_postgres_rows, { 'id' => 1 })
    end.to raise_error(TypeError, 'Postgres row lookup must return an array')
  end

  it 'rejects a non-object row within a Postgres lookup result' do
    expect do
      realtime.__send__(:validate_postgres_rows, [{ 'id' => 1 }, nil])
    end.to raise_error(TypeError, 'Postgres row lookup must return objects')
  end
end
