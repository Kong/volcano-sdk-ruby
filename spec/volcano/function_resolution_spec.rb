# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::FunctionResolution do
  let(:calls) { [] }
  let(:resolve_payload) do
    {
      'name' => 'send-welcome',
      'function_id' => function_id,
      'cache_ttl_seconds' => 60
    }
  end
  let(:resolve_status) { 200 }
  # statuses drive successive invocations; a nil version marks a platform error.
  let(:invoke_plan) { { statuses: [200], version: 'v1' } }

  let(:transport) do
    call_log = calls
    payload = resolve_payload
    status = resolve_status
    statuses = invoke_plan.fetch(:statuses).dup
    version = invoke_plan.fetch(:version)
    Object.new.tap do |fake|
      fake.define_singleton_method(:resolve_function_for_invocation) do |**arguments|
        call_log << [:resolve_function_for_invocation, arguments]
        Volcano::Transport::Response.new(status: status, body: payload, headers: {}, data: nil)
      end
      %i[invoke_function invoke_function_url].each do |operation|
        fake.define_singleton_method(operation) do |**arguments|
          call_log << [operation, arguments]
          invoke_status = statuses.length > 1 ? statuses.shift : statuses.first
          headers = version.nil? ? {} : { 'X-Volcano-Version' => version }
          Volcano::Transport::Response.new(
            status: invoke_status, body: { 'ok' => true }, headers: headers, data: nil
          )
        end
      end
    end
  end

  def function_id
    '00000000-0000-4000-8000-000000000040'
  end

  def invoke_url
    "https://#{function_id}.functions.test.run/"
  end

  def client(service_key: 'service-key', api_url: nil)
    arguments = { anon_key: 'anon-key', service_key: service_key, _transport: transport }
    arguments[:api_url] = api_url if api_url
    Volcano::Client.new(**arguments)
  end

  def resolve_calls
    calls.count { |operation, _| operation == :resolve_function_for_invocation }
  end

  context 'when the server supplies an invocation endpoint' do
    let(:resolve_payload) { super().merge('invoke_url' => invoke_url) }

    it 'invokes the resolved endpoint rather than the API path', :aggregate_failures do
      client.functions.invoke('send-welcome', { 'user_id' => 'u-1' })

      expect(calls.map(&:first)).to eq(%i[resolve_function_for_invocation invoke_function_url])
      expect(calls[1].last).to eq(
        authorization: 'service-key', invoke_url: invoke_url, payload: { 'user_id' => 'u-1' }
      )
    end

    it 'resolves a name once for repeated invocations', :aggregate_failures do
      instance = client
      3.times { instance.functions.invoke('send-welcome') }

      expect(resolve_calls).to eq(1)
      expect(calls.count { |operation, _| operation == :invoke_function_url }).to eq(3)
    end
  end

  it 'falls back to the API path without an invocation endpoint' do
    client.functions.invoke('send-welcome')

    expect(calls.map(&:first)).to eq(%i[resolve_function_for_invocation invoke_function])
  end

  # 'http://...' would downgrade a token the https API keeps encrypted; the
  # rest are malformed, and must fall back rather than reach the transport.
  ['', 'not-a-url', 'ftp://example.test/', '/relative', 'http://functions.test.run/',
   'https://[', 'https://[::1', 'https://example.test:99999/', 'https://exa mple.test/'].each do |unusable|
    context "when the invocation endpoint is #{unusable.inspect}" do
      let(:resolve_payload) { super().merge('invoke_url' => unusable) }

      it 'ignores it and uses the API path' do
        client.functions.invoke('send-welcome')

        expect(calls.map(&:first).last).to eq(:invoke_function)
      end
    end
  end

  context 'when the API itself is plaintext' do
    let(:resolve_payload) { super().merge('invoke_url' => 'http://127.0.0.1:9/') }

    it 'accepts a plaintext invocation endpoint' do
      client(api_url: 'http://127.0.0.1:8000').functions.invoke('send-welcome')

      expect(calls.map(&:first).last).to eq(:invoke_function_url)
    end
  end

  it 'resolves again once the advertised lifetime expires', :aggregate_failures do
    instance = client
    instance.functions.invoke('send-welcome')

    allow(described_class).to receive(:now).and_return(described_class.now + 59)
    instance.functions.invoke('send-welcome')
    expect(resolve_calls).to eq(1)

    allow(described_class).to receive(:now).and_return(described_class.now + 61)
    instance.functions.invoke('send-welcome')
    expect(resolve_calls).to eq(2)
  end

  it 'does not share a resolution across credentials' do
    client(service_key: 'service-key').functions.invoke('send-welcome')
    client(service_key: 'other-key').functions.invoke('send-welcome')

    expect(resolve_calls).to eq(2)
  end

  it 'shares a resolution across clients using one credential' do
    client.functions.invoke('send-welcome')
    client.functions.invoke('send-welcome')

    expect(resolve_calls).to eq(1)
  end

  [0, -1, nil, '60', 1.5].each do |ttl|
    context "when the advertised lifetime is #{ttl.inspect}" do
      let(:resolve_payload) { super().merge('cache_ttl_seconds' => ttl) }

      it 'rejects the resolve response' do
        expect { client.functions.invoke('send-welcome') }
          .to raise_error(TypeError, 'Expected a complete function response')
      end
    end
  end

  context 'when the cached identity is gone' do
    # A recreated function gets a new id, so the cached one answers 404. No
    # version header: the 404 comes from the platform, not the function.
    let(:invoke_plan) { { statuses: [404, 200], version: nil } }

    it 'resolves again and retries once', :aggregate_failures do
      result = client.functions.invoke('send-welcome')

      expect(result.status).to eq(200)
      expect(calls.map(&:first)).to eq(
        %i[resolve_function_for_invocation invoke_function resolve_function_for_invocation invoke_function]
      )
    end
  end

  context 'when the function itself answers 404' do
    let(:invoke_plan) { { statuses: [404], version: 'v1' } }

    it 'returns that response without invoking twice', :aggregate_failures do
      result = client.functions.invoke('send-welcome')

      expect(result.status).to eq(404)
      expect(calls.count { |operation, _| operation == :invoke_function }).to eq(1)
    end
  end

  context 'when the name does not resolve' do
    let(:resolve_status) { 404 }
    let(:resolve_payload) { { 'error' => 'function not found' } }

    it 'remembers the miss rather than re-resolving', :aggregate_failures do
      instance = client
      3.times do
        expect { instance.functions.invoke('missing-function') }
          .to raise_error(Volcano::Error::NotFoundError)
      end

      expect(resolve_calls).to eq(1)
    end
  end
end
