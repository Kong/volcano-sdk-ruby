# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:calls) { [] }
  let(:invoke_responses) do
    [
      Volcano::Transport::Response.new(
        status: 200,
        body: { 'message' => 'hello', 'items' => [1, 2] },
        headers: { 'X-Volcano-Version' => 'staging-v1', 'X-Trace' => 'trace-1' },
        data: nil
      )
    ]
  end
  let(:transport) do
    call_log = calls
    responses = invoke_responses
    Object.new.tap do |fake|
      fake.define_singleton_method(:resolve_function_for_invocation) do |**arguments|
        call_log << [:resolve_function_for_invocation, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'name' => arguments.fetch(:name),
            'function_id' => '00000000-0000-4000-8000-000000000040',
            'cache_ttl_seconds' => 60
          },
          headers: {}, data: nil
        )
      end
      fake.define_singleton_method(:invoke_function) do |**arguments|
        call_log << [:invoke_function, arguments]
        responses.last
      end
    end
  end
  let(:client) do
    described_class.new(
      anon_key: 'anon-key', service_key: 'service-key', _transport: transport
    )
  end

  it 'resolves and invokes a function by name', :aggregate_failures do
    result = client.functions.invoke('send-welcome', { 'user_id' => 'user-123' })

    expect(result).to have_attributes(status: 200, version: 'staging-v1')
    expect(result.data).to eq('message' => 'hello', 'items' => [1, 2]).and be_frozen
    expect(result.data.fetch('items')).to be_frozen
    expect(result.headers).to eq(
      'X-Volcano-Version' => 'staging-v1', 'X-Trace' => 'trace-1'
    ).and be_frozen
    expect(calls.map(&:first)).to eq(%i[resolve_function_for_invocation invoke_function])
    expect(calls[0].last).to eq(authorization: 'service-key', name: 'send-welcome')
    expect(calls[1].last).to eq(
      authorization: 'service-key',
      function_id: '00000000-0000-4000-8000-000000000040',
      payload: { 'user_id' => 'user-123' }
    )
  end

  it 'returns a function-owned error response' do
    invoke_responses << Volcano::Transport::Response.new(
      status: 422, body: { 'error' => 'invalid order' },
      headers: { 'x-volcano-version' => 'v2' }, data: nil
    )

    result = client.functions.invoke('validate-order')

    expect(result).to have_attributes(
      status: 422, data: { 'error' => 'invalid order' }, version: 'v2'
    )
  end

  it 'returns an empty successful function response' do
    invoke_responses << Volcano::Transport::Response.new(
      status: 204, body: nil, headers: { 'x-volcano-version' => 'v2' }, data: nil
    )

    result = client.functions.invoke('run-cleanup')

    expect(result).to have_attributes(status: 204, data: nil, version: 'v2')
  end

  it 'raises for a platform failure' do
    invoke_responses << Volcano::Transport::Response.new(
      status: 503,
      body: { 'error' => 'function is provisioning', 'code' => 'function_not_ready' },
      headers: {}, data: nil
    )

    expect { client.functions.invoke('daily-rollup') }
      .to raise_error(Volcano::Error::ServerError, 'function is provisioning') do |error|
        expect(error).to have_attributes(status: 503, code: 'function_not_ready')
      end
  end

  it 'rejects invalid names before transport' do
    ['', ' Invalid ', '-leading', 'a' * 64].each do |name|
      expect { client.functions.invoke(name) }.to raise_error(ArgumentError, /DNS-safe/)
    end

    expect(calls).to be_empty
  end

  it 'uses the local anon key without a session or service key' do
    anon_key = 'ak-0000000000000000000000000000000000000000'
    public_client = described_class.new(anon_key: anon_key, _transport: transport)

    public_client.functions.invoke('public-health')

    expect(calls.map { |_, arguments| arguments.fetch(:authorization) })
      .to eq([anon_key, anon_key])
  end
end
