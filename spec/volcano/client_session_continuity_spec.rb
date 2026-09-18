# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) do
    described_class.new(anon_key: 'anon', access_token: token('session-a'), refresh_token: 'refresh',
                        _transport: transport)
  end

  def token(session_id, renewed: false)
    payload = [{ session_id: session_id, renewed: renewed }.to_json].pack('m0').tr('+/', '-_').delete('=')
    "header.#{payload}.signature"
  end

  def response(status, body = nil)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def refresh_response(session_id, user_id = 'user-a')
    response(200, 'access_token' => token(session_id, renewed: true), 'refresh_token' => 'rotated',
                  'user' => { 'id' => user_id, 'email' => 'u@example.com', 'status' => 'active' })
  end

  %w[user-a user-b].product([false, true]).each do |user_id, profile_first|
    it "rejects a different session for #{user_id}, profile validated: #{profile_first}" do
      allow(transport).to receive_messages(
        auth_get_user: response(200, 'user' => { 'id' => 'user-a', 'email' => 'u@example.com', 'status' => 'active' }),
        auth_refresh: refresh_response('session-b', user_id),
        query_database_insert: response(401, 'error' => 'expired')
      )
      client.auth.user if profile_first
      expect { client.database('main').from('items').insert(name: 'example').execute }
        .to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(:query_database_insert).once
      expect(client.current_session.access_token).to eq(token('session-a'))
    end
  end

  it 'rejects unidentified bootstrap refresh before I/O' do
    unbound = described_class.new(anon_key: 'anon', access_token: 'malformed', refresh_token: 'refresh',
                                  _transport: transport)
    expect { unbound.auth.refresh_session }.to raise_error(Volcano::Error::AuthenticationError, /session identifier/)
  end

  [false, true].each do |replace|
    it "renews expired access for revocation, preserving explicit replacement: #{replace}" do
      replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'other-user')
      allow(transport).to receive(:auth_delete_my_session).and_return(response(401, 'error' => 'expired'),
                                                                      response(204))
      allow(transport).to receive(:auth_refresh) do
        client.auth.current_session = replacement if replace
        refresh_response('session-a')
      end
      if replace
        expect { client.auth.sign_out }.to raise_error(Volcano::Error::SessionChangedError)
      else
        client.auth.sign_out
      end
      expect(transport).to have_received(:auth_delete_my_session)
        .with(authorization: token('session-a', renewed: true), session_id: 'session-a').once
      expect(client.current_session).to eq(replace ? replacement : nil)
    end
  end

  it 'clears a concurrent refresh of the revoked lineage' do
    allow(transport).to receive(:auth_refresh).and_return(refresh_response('session-a'))
    allow(transport).to receive(:auth_delete_my_session) do
      client.auth.refresh_session
      response(204)
    end
    client.auth.sign_out
    expect(client.current_session).to be_nil
  end

  it 'does not revoke an unrelated session while recovering expired access' do
    allow(transport).to receive_messages(auth_delete_my_session: response(401, 'error' => 'expired'),
                                         auth_refresh: refresh_response('session-b'))
    expect { client.auth.sign_out }.to raise_error(Volcano::Error::AuthenticationError, /different server session/)
    expect(transport).to have_received(:auth_delete_my_session).once
    expect(client.current_session).to be_nil
  end
end
