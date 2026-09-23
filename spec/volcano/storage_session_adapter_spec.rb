# frozen_string_literal: true

RSpec.describe Volcano::StorageSessionAdapter do
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access') }
  let(:session_adapter) { described_class.new(client) }

  it 'accepts prevalidated adapters through both public constructors' do
    transport = Volcano::StorageTransportAdapter.new(Object.new)
    storage = Volcano::Storage.new(session_adapter, transport, api_url: 'https://api.example.test', anon_key: 'anon')

    expect(storage.from('assets')).to be_a(Volcano::StorageBucket)
    expect do
      Volcano::StorageBucket.new(session_adapter, transport, 'assets',
                                 api_url: 'https://api.example.test', anon_key: 'anon')
    end.not_to raise_error
  end

  it 'rejects an invalid direct session token' do
    allow(client).to receive(:session_token).and_return(42)

    expect { session_adapter.session_token }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage session token')
  end

  it 'rejects an invalid token yielded during a scoped request' do
    allow(client).to receive(:session_request) { |**_options, &block| block.call(42) }

    expect { session_adapter.session_request(binding: client.capture_session_binding) { |_token| nil } }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage session token')
  end

  it 'rejects a non-response returned by a scoped request' do
    allow(client).to receive(:session_request).and_return(42)

    expect { session_adapter.session_request(binding: client.capture_session_binding) { |_token| nil } }
      .to raise_error(Volcano::Error::TransportError, 'invalid storage session response')
  end

  it 'rejects malformed session bindings before making a request' do
    binding = client.capture_session_binding
    invalid = [nil, [0, binding.fetch(1)], ['old', binding.fetch(1), binding.fetch(2)],
               [0, Object.new, binding.fetch(2)], [0, binding.fetch(1), Object.new]]

    invalid.each do |value|
      allow(client).to receive(:capture_session_binding).and_return(value)
      expect { session_adapter.capture_session_binding }
        .to raise_error(Volcano::Error::TransportError, 'invalid storage session binding')
    end
  end

  it 'rejects a non-response from the generated storage transport' do
    transport = instance_double(Volcano.const_get(:GeneratedTransport))
    allow(transport).to receive(:list_storage_objects).and_return('bad response')

    expect do
      Volcano::StorageTransportAdapter.new(transport).list_storage_objects(
        authorization: 'access', bucket_name: 'assets', prefix: '', limit: nil, cursor: nil
      )
    end.to raise_error(Volcano::Error::TransportError, 'invalid storage transport response')
  end
end
