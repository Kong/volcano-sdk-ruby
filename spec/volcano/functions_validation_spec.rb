# frozen_string_literal: true

module Volcano
  RSpec.describe Functions do
    let(:transport) { instance_double(GeneratedTransport) }
    let(:client) { Volcano::Client.new(anon_key: 'anon-key', _transport: transport) }

    [nil, false, 1, [], 'invalid'].each do |value|
      it "rejects a non-object invocation payload before transport: #{value.inspect}" do
        expect { client.functions.invoke('echo', value) }.to raise_error(TypeError, 'Function payload must be a Hash')
      end

      it "rejects a non-object resolution before invoking a function: #{value.inspect}" do
        allow(transport).to receive(:resolve_function_for_invocation).with(authorization: 'anon-key', name: 'echo')
                                                                     .and_return(response(value))

        expect { client.functions.invoke('echo') }.to raise_error(TypeError, 'Expected a complete function response')
      end
    end

    it 'returns a successful response without headers' do
      allow(transport).to receive(:resolve_function_for_invocation).with(authorization: 'anon-key', name: 'echo')
                                                                   .and_return(response('function_id' => 'id',
                                                                                        'cache_ttl_seconds' => 60))
      allow(transport).to receive(:invoke_function).with(authorization: 'anon-key', function_id: 'id', payload: {})
                                                   .and_return(response('result'))

      expect(client.functions.invoke('echo')).to have_attributes(data: 'result', status: 200, headers: {}, version: nil)
    end

    it 'rejects a resolution without a function ID' do
      allow(transport).to receive(:resolve_function_for_invocation)
        .and_return(response('cache_ttl_seconds' => 60))

      expect { client.functions.invoke('echo') }.to raise_error(TypeError, 'Expected a complete function response')
    end

    it 'rejects malformed names before requesting any credential-scoped resolution' do
      allow(transport).to receive(:resolve_function_for_invocation)
      check_property(PropCheck::Generators.printable_string) do |suffix|
        expect { client.functions.invoke(".#{suffix}") }.to raise_error(ArgumentError)
      end

      expect(transport).not_to have_received(:resolve_function_for_invocation)
    end

    private

    def response(body) = Volcano::Transport::Response.new(status: 200, body: body, headers: nil, data: nil)
  end
end
