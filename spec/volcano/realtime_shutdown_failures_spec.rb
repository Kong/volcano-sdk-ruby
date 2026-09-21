# frozen_string_literal: true

require 'async'
require 'spec_helper'
require 'support/fake_realtime'
require 'support/protocol_socket'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:client) do
    Volcano::Client.new(anon_key: 'anon-secret', access_token: 'access-secret',
                        _realtime_socket_factory: ->(_address) { socket })
  end

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  it 'redacts disconnect failures and leaves the facade closed' do
    channel = client.realtime.channel('room')
    allow(channel).to receive(:mark_closed).and_raise(IOError, 'close failed: anon-secret access-secret')

    expect { client.realtime.disconnect }.to raise_error(Volcano::Error::TransportError) do |error|
      expect(error.message).not_to include('anon-secret', 'access-secret')
      expect(error.cause).to be_nil
    end
    expect { client.realtime.channel('another') }.to raise_error(Volcano::Realtime::ClosedError)
  end

  it 'never supplies a replacement session token to a request from the previous connection' do
    client.realtime.channel('public:messages', type: :postgres).subscribe
    lineage = client.capture_session_binding[1]
    client.auth.current_session = Volcano::Session.new('replacement-secret', 'refresh', 'replacement-user')

    expect { client.realtime.__send__(:access_token_for_protocol_lineage, lineage) }
      .to raise_error(Volcano::Error::SessionChangedError)
  end
end
