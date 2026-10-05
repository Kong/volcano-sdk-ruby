# frozen_string_literal: true

require 'spec_helper'
require 'support/session_fixtures'

RSpec.describe Volcano::Functions do
  include SessionFixtures

  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:payload) { { 'values' => ['original'] } }
  let(:resolved) { response(200, 'name' => 'echo', 'function_id' => 'function-id', 'cache_ttl_seconds' => 60) }
  let(:invoked) { response(200, 'ok' => true) }

  def rejected = response(401, 'error' => 'original denial', 'code' => 'original')

  def response(status, body, headers = {})
    Volcano::Transport::Response.new(status: status, body: body, headers: headers, data: nil)
  end

  def refreshed
    response(200, 'access_token' => access_token('new'), 'refresh_token' => 'new-refresh',
                  'user' => { 'id' => 'user', 'email' => 'user@example.com', 'status' => 'active' })
  end

  before do
    client.auth.current_session = Volcano::Session.new(access_token('old'), 'old-refresh', 'user')
    allow(transport).to receive_messages(resolve_function_for_invocation: resolved, invoke_function: invoked,
                                         auth_refresh: refreshed)
  end

  %i[resolve_function_for_invocation invoke_function].each do |operation|
    it "refreshes a rejected #{operation} once and preserves payload values" do
      requests = []
      allow(transport).to receive(operation) do |**request|
        requests << request
        next rejected if requests.length == 1

        operation == :invoke_function ? invoked : resolved
      end
      allow(transport).to receive(:auth_refresh) do
        payload.fetch('values') << 'changed'
        refreshed
      end

      expect(client.functions.invoke('echo', payload).data).to eq('ok' => true)
      expect(requests.map { |request| request.fetch(:authorization) }).to eq([access_token('old'), access_token('new')])
      expect(transport).to have_received(:invoke_function).with(
        authorization: access_token('new'), function_id: 'function-id', payload: { 'values' => ['original'] }
      )
      expect(transport).to have_received(:auth_refresh).once
    end

    it "rejects session replacement during #{operation}" do
      allow(transport).to receive(operation) do
        client.auth.current_session = Volcano::Session.new(access_token('replacement'), 'replacement-refresh', 'user')
        operation == :invoke_function ? invoked : resolved
      end

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session.refresh_token).to eq('replacement-refresh')
      expect(transport).not_to have_received(:invoke_function) if operation == :resolve_function_for_invocation
    end
  end

  [401, 403].each do |status|
    it "returns a function's own #{status} without refreshing or replaying" do
      allow(transport).to receive(:invoke_function).and_return(
        response(status, { 'error' => 'application response' }, 'X-Volcano-Function-Invoked' => 'true')
      )

      expect(client.functions.invoke('echo').status).to eq(status)
      expect(transport).not_to have_received(:auth_refresh)
      expect(transport).to have_received(:invoke_function).once
    end
  end

  [200, 401, 503].each do |status|
    it "bounds retries and preserves the original rejection when refresh returns #{status}" do
      allow(transport).to receive(:resolve_function_for_invocation).and_return(rejected)
      unless status == 200
        allow(transport).to receive(:auth_refresh).and_return(response(status,
                                                                       'error' => 'refresh failed'))
      end

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::AuthenticationError, /original denial/)
      expect(transport).to have_received(:auth_refresh).once
      expect(transport).to have_received(:resolve_function_for_invocation).exactly(status == 200 ? 2 : 1).times
    end
  end

  %i[resolve_function_for_invocation invoke_function].each do |operation|
    it "never replays a platform 403 from #{operation}" do
      allow(transport).to receive(operation).and_return(response(403, 'error' => 'forbidden'))

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::VolcanoError)
      expect(transport).to have_received(operation).once
      expect(transport).not_to have_received(:auth_refresh)
    end

    it "never replays an uncertain network failure from #{operation}" do
      allow(transport).to receive(operation).and_raise(IOError, 'connection lost')

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::TransportError)
      expect(transport).to have_received(operation).once
      expect(transport).not_to have_received(:auth_refresh)
    end
  end

  %w[anon service].each do |key|
    it "never refreshes a rejected #{key} key" do
      target = Volcano::Client.new(anon_key: 'anon', service_key: key == 'service' ? key : nil, _transport: transport)
      allow(transport).to receive(:resolve_function_for_invocation).and_return(rejected)

      expect { target.functions.invoke('echo') }.to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(:resolve_function_for_invocation).with(authorization: key, name: 'echo').once
      expect(transport).not_to have_received(:auth_refresh)
    end
  end

  %i[refresh listener].each do |replace_at|
    it "prevents dispatch when #{replace_at} replaces the session" do
      replacement = Volcano::Session.new(access_token('replacement'), 'replacement-refresh', 'user')
      allow(transport).to receive(:resolve_function_for_invocation).and_return(rejected)
      allow(transport).to receive(:auth_refresh) do
        client.auth.current_session = replacement if replace_at == :refresh
        refreshed
      end
      client.auth.on_auth_state_change do |event, _session|
        client.auth.current_session = replacement if replace_at == :listener && event == :token_refreshed
      end

      expect { client.functions.invoke('echo') }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(transport).not_to have_received(:invoke_function)
    end
  end

  [200, 401].each do |status|
    it "shares one concurrent refresh returning #{status}" do
      arrived = Queue.new
      release = Queue.new
      allow(transport).to receive(:invoke_function) do |authorization:, **|
        next invoked unless authorization == access_token('old')

        arrived << true
        release.pop(timeout: 5)
        rejected
      end
      allow(transport).to receive(:auth_refresh).and_return(status == 200 ? refreshed : rejected)
      calls = Array.new(2) { Thread.new { invoke_outcome } }
      outcomes = complete_calls(calls, arrived, release)
      expect(outcomes).to eq(status == 200 ? [200, 200] : ['original denial', 'original denial'])
      expect(transport).to have_received(:auth_refresh).once
    ensure
      calls&.each { |thread| thread.kill if thread.alive? }
    end
  end

  it 'refreshes a rejected resolved invocation URL without falling back to the API' do
    url = 'https://echo.functions.test.volcano.dev/invoke'
    allow(transport).to receive(:resolve_function_for_invocation).and_return(
      response(200, 'name' => 'echo', 'function_id' => 'function-id', 'cache_ttl_seconds' => 60, 'invoke_url' => url)
    )
    allow(transport).to receive(:invoke_function_url).and_return(rejected, invoked)

    expect(client.functions.invoke('echo', payload).status).to eq(200)
    expect(transport).to have_received(:invoke_function_url).with(
      authorization: access_token('new'), invoke_url: url, payload: payload
    )
    expect(transport).not_to have_received(:invoke_function)
    expect(transport).to have_received(:auth_refresh).once
  end

  it 'refreshes the token captured at each rejected stage' do
    allow(transport).to receive(:resolve_function_for_invocation).and_return(rejected, resolved)
    allow(transport).to receive(:invoke_function).and_return(rejected, invoked)

    expect(client.functions.invoke('echo').status).to eq(200)
    expect(transport).to have_received(:auth_refresh).twice
  end

  def complete_calls(calls, arrived, release)
    2.times { arrived.pop(timeout: 5) }
    2.times { release << true }
    calls.map { |thread| thread.join(5)&.value }
  end

  def invoke_outcome
    client.functions.invoke('echo').status
  rescue Volcano::Error::AuthenticationError => e
    e.message
  end
end
