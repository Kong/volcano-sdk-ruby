# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { described_class.new(anon_key: 'anon', _transport: transport) }
  let(:session) { Volcano::Session.new('access-1', 'refresh-1', 'user') }
  let(:refresh_body) { { 'access_token' => 'access-2', 'refresh_token' => 'refresh-2', 'user' => { 'id' => 'user' } } }

  def response(status, body = nil)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  before { client.auth.current_session = session }

  [
    [:request_email_change, [[], { new_email: 'new@example.com' }], :auth_request_email_change, 200, {}],
    [:cancel_email_change, [[], {}], :auth_cancel_email_change, 200, {}],
    [:list_sessions, [[], { page: 2, limit: 10 }], :auth_get_my_sessions, 200,
     { 'sessions' => [], 'total' => 0, 'page' => 2, 'limit' => 10, 'total_pages' => 0 }],
    [:delete_all_other_sessions, [[], {}], :auth_delete_all_my_sessions, 204, nil],
    [:delete_session, [['00000000-0000-4000-8000-000000000009'], {}], :auth_delete_my_session, 204, nil],
    [:list_linked_oauth_providers, [[], {}], :auth_list_oauth_providers, 200, { 'providers' => [] }],
    [:link_oauth_provider, [['github'], {}], :auth_link_oauth_provider, 200,
     { 'authorization_url' => 'https://provider.example/authorize' }],
    [:unlink_oauth_provider, [['github'], {}], :auth_unlink_oauth_provider, 204, nil],
    [:get_oauth_provider_token, [['github'], {}], :auth_get_oauth_provider_token, 200,
     { 'message' => 'valid', 'provider' => 'github', 'expires_in' => 30 }],
    [:refresh_oauth_provider_token, [['github'], {}], :auth_refresh_oauth_provider_token, 200,
     { 'message' => 'valid', 'provider' => 'github', 'expires_in' => 30 }],
    [:call_oauth_api, [['github'], { endpoint: '/user', method: 'POST', body: { 'name' => 'original' } }],
     :auth_call_oauth_api, 200, { 'data' => { 'ok' => true } }]
  ].each do |operation, call, transport_operation, status, body|
    context operation.to_s do
      let(:invoke_operation) { -> { client.auth.public_send(operation, *call[0], **call[1]) } }

      it 'refreshes once after 401 and replays with the new credential' do
        allow(transport).to receive(transport_operation).and_return(response(401), response(status, body))
        allow(transport).to receive(:auth_refresh).and_return(response(200, refresh_body))
        invoke_operation.call
        expect(transport).to have_received(transport_operation).with(hash_including(authorization: 'access-1')).once
        expect(transport).to have_received(transport_operation).with(hash_including(authorization: 'access-2')).once
        expect(transport).to have_received(:auth_refresh).with(authorization: 'anon', refresh_token: 'refresh-1').once
        expect(client.current_session.access_token).to eq('access-2')
      end

      it 'bounds repeated authentication rejection to one refresh' do
        allow(transport).to receive(transport_operation).and_return(response(401))
        allow(transport).to receive(:auth_refresh).and_return(response(200, refresh_body))
        expect { invoke_operation.call }.to raise_error(Volcano::Error::AuthenticationError)
        expect(transport).to have_received(transport_operation).twice
        expect(transport).to have_received(:auth_refresh).once
      end

      it 'does not refresh or replay an ambiguous transport failure' do
        allow(transport).to receive(transport_operation).and_raise(IOError, 'response lost')
        expect { invoke_operation.call }.to raise_error(Volcano::Error::TransportError)
        expect(transport).to have_received(transport_operation).once
      end

      it 'does not refresh or replay an availability failure' do
        allow(transport).to receive(transport_operation).and_return(response(503))
        expect { invoke_operation.call }.to raise_error(Volcano::Error::ServerError)
        expect(transport).to have_received(transport_operation).once
      end

      it 'preserves a replacement session and never replays with it' do
        replacement = Volcano::Session.new('other', 'other-refresh', 'other-user')
        allow(transport).to receive(transport_operation) do
          client.auth.current_session = replacement
          response(401)
        end
        expect { invoke_operation.call }.to raise_error(Volcano::Error::SessionChangedError)
        expect(transport).to have_received(transport_operation).once
        expect(client.current_session).to eq(replacement)
      end
    end
  end
  def access_token(session_id, renewed: false)
    payload = [{ session_id: session_id, renewed: renewed }.to_json].pack('m0').tr('+/', '-_').delete('=')
    "header.#{payload}.signature"
  end

  it 'clears the current session after an authenticated deletion refreshes it' do
    session_id = '00000000-0000-4000-8000-000000000001'
    client.auth.current_session = Volcano::Session.new(access_token(session_id), 'refresh-1', 'user')
    refreshed = refresh_body.merge('access_token' => access_token(session_id, renewed: true))
    allow(transport).to receive(:auth_refresh).and_return(response(200, refreshed))
    allow(transport).to receive(:auth_delete_my_session).and_return(response(401), response(204))
    client.auth.delete_session(session_id)
    expect(client.current_session).to be_nil
    expect(transport).to have_received(:auth_delete_my_session)
      .with(authorization: refreshed.fetch('access_token'), session_id: session_id).once
  end

  it 'clears a refresh descendant when deletion already succeeded' do
    session_id = '00000000-0000-4000-8000-000000000001'
    client.auth.current_session = Volcano::Session.new(access_token(session_id), 'refresh-1', 'user')
    refreshed = refresh_body.merge('access_token' => access_token(session_id, renewed: true))
    allow(transport).to receive(:auth_refresh).and_return(response(200, refreshed))
    allow(transport).to receive(:auth_delete_my_session) do
      client.auth.refresh_session
      response(204)
    end
    client.auth.delete_session(session_id)
    expect(client.current_session).to be_nil
  end

  it 'snapshots the requested email before an authenticated retry' do
    email = +'new@example.com'
    calls = []
    allow(transport).to receive(:auth_request_email_change) do |**arguments|
      calls << arguments
      email.replace('changed@example.com')
      response(calls.length == 1 ? 401 : 200, {})
    end
    allow(transport).to receive(:auth_refresh).and_return(response(200, refresh_body))
    client.auth.request_email_change(new_email: email)
    expect(calls.map { |call| call.fetch(:new_email) }).to eq(['new@example.com', 'new@example.com'])
  end

  it 'snapshots the OAuth provider, endpoint, method and nested body for replay' do
    provider, endpoint, method = %w[github /user POST].map(&:dup)
    body = { 'names' => ['original'] }
    calls = []
    allow(transport).to receive(:auth_call_oauth_api) do |**arguments|
      calls << arguments
      provider.replace('google')
      endpoint.replace('/changed')
      method.replace('GET')
      body['names'] << 'changed'
      response(calls.length == 1 ? 401 : 200, 'data' => {})
    end
    allow(transport).to receive(:auth_refresh).and_return(response(200, refresh_body))
    client.auth.call_oauth_api(provider, endpoint: endpoint, method: method, body: body)
    expect(calls.map { |call| call.except(:authorization) }).to eq(
      Array.new(2, { provider: 'github', endpoint: '/user', method: 'POST', body: { 'names' => ['original'] } })
    )
  end

  it 'captures ownership before OAuth request serialization' do
    replacement = Volcano::Session.new('other', 'other-refresh', 'other-user')
    body = { 'name' => 'original' }
    allow(JSON).to receive(:generate).with(body).and_wrap_original do |original, *args|
      client.auth.current_session = replacement
      original.call(*args)
    end
    expect { client.auth.call_oauth_api('github', endpoint: '/user', body: body) }
      .to raise_error(Volcano::Error::SessionChangedError)
    expect(client.current_session).to eq(replacement)
  end
end
