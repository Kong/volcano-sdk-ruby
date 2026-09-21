# frozen_string_literal: true

RSpec.describe Volcano::Functions do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:replacement) { Volcano::Session.new('replacement', 'replacement-refresh', 'other') }
  let(:resolved) { response(200, 'function_id' => 'function-id', 'cache_ttl_seconds' => 60) }
  let(:invoked) { response(200, 'ok' => true) }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  before do
    allow(transport).to receive_messages(resolve_function_for_invocation: resolved, invoke_function: invoked)
    allow(transport).to receive(:auth_refresh)
  end

  %i[resolve_function_for_invocation invoke_function].each do |operation|
    it "rejects anonymous #{operation} completion after session adoption" do
      allow(transport).to receive(operation) do
        client.auth.current_session = replacement
        operation == :invoke_function ? invoked : resolved
      end

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(transport).to have_received(operation).with(hash_including(authorization: 'anon')).once
      expect(transport).not_to have_received(:auth_refresh)
      expect(transport).not_to have_received(:invoke_function) if operation == :resolve_function_for_invocation
    end

    it "does not retry anonymous #{operation} rejection under an adopted session" do
      allow(transport).to receive(operation) do
        client.auth.current_session = replacement
        response(401, 'error' => 'old credential rejected')
      end

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(transport).to have_received(operation).with(hash_including(authorization: 'anon')).once
      expect(transport).not_to have_received(:auth_refresh)
    end
  end
end
