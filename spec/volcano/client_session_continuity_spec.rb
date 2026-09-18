# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:session_a) { '00000000-0000-4000-8000-000000000001' }
  let(:session_b) { '00000000-0000-4000-8000-000000000002' }
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) do
    described_class.new(anon_key: 'anon', access_token: token(session_a), refresh_token: 'refresh',
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
        auth_refresh: refresh_response(session_b, user_id),
        query_database_insert: response(401, 'error' => 'expired')
      )
      client.auth.user if profile_first
      expect { client.database('main').from('items').insert(name: 'example').execute }
        .to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(:query_database_insert).once
      expect(client.current_session.access_token).to eq(token(session_a))
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
        refresh_response(session_a)
      end
      if replace
        expect { client.auth.sign_out }.to raise_error(Volcano::Error::SessionChangedError)
      else
        client.auth.sign_out
      end
      expect(transport).to have_received(:auth_delete_my_session)
        .with(authorization: token(session_a, renewed: true), session_id: session_a).once
      expect(client.current_session).to eq(replace ? replacement : nil)
    end
  end

  it 'clears a concurrent refresh of the revoked lineage' do
    allow(transport).to receive(:auth_refresh).and_return(refresh_response(session_a))
    allow(transport).to receive(:auth_delete_my_session) do
      client.auth.refresh_session
      response(204)
    end
    client.auth.sign_out
    expect(client.current_session).to be_nil
  end

  it 'does not revoke an unrelated session while recovering expired access' do
    allow(transport).to receive_messages(auth_delete_my_session: response(401, 'error' => 'expired'),
                                         auth_refresh: refresh_response(session_b))
    expect { client.auth.sign_out }.to raise_error(Volcano::Error::AuthenticationError, /different server session/)
    expect(transport).to have_received(:auth_delete_my_session).once
    expect(client.current_session).to be_nil
  end

  def stub_refresh_owner(entered, release)
    allow(transport).to receive(:auth_refresh) do
      entered << true
      Timeout.timeout(2) { release.pop }
      refresh_response(session_a)
    end
  end

  def signal_logout_capture(captured)
    allow(transport).to receive(:auth_delete_my_session).and_return(response(204))
    allow(client).to receive(:capture_session_binding).and_wrap_original do |original|
      original.call.tap { captured << true if Thread.current.name == 'logout' }
    end
  end

  def refresh_thread
    Thread.new do
      client.auth.refresh_session
    rescue Volcano::Error::SessionChangedError
      nil
    end
  end

  def logout_thread
    Thread.new do
      Thread.current.name = 'logout'
      client.auth.sign_out
    end
  end

  def complete_refresh_and_logout(entered, release, captured)
    refreshing = refresh_thread
    Timeout.timeout(2) { entered.pop }
    signing_out = logout_thread
    Timeout.timeout(2) { captured.pop }
    release << true
    [refreshing, signing_out].each(&:value)
  ensure
    release << true if release.empty?
    [refreshing, signing_out].compact.each { |thread| thread.join(2) }
  end

  it 'waits for the refresh owner and revokes its rotated credentials' do
    entered = Queue.new
    release = Queue.new
    captured = Queue.new
    stub_refresh_owner(entered, release)
    signal_logout_capture(captured)
    complete_refresh_and_logout(entered, release, captured)
    expect(transport).to have_received(:auth_delete_my_session)
      .with(authorization: token(session_a, renewed: true), session_id: session_a).once
    expect(transport).to have_received(:auth_refresh).once
    expect(client.current_session).to be_nil
  end

  it 'uses refresh-token logout for a malformed session claim' do
    malformed = described_class.new(anon_key: 'anon', access_token: token('../invalid'), refresh_token: 'refresh',
                                    _transport: transport)
    allow(transport).to receive(:auth_logout).and_return(response(204))
    malformed.auth.sign_out
    expect(transport).to have_received(:auth_logout).with(authorization: 'anon', refresh_token: 'refresh').once
    expect(malformed.current_session).to be_nil
  end
end
