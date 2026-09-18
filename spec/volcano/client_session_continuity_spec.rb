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

  it 'prevents a new refresh after sign-out claims the session' do
    allow(transport).to receive(:auth_refresh).and_return(refresh_response(session_a))
    allow(transport).to receive(:auth_delete_my_session) do
      expect { client.auth.refresh_session }.to raise_error(Volcano::Error::SessionChangedError)
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
    allow(transport).to receive_messages(auth_delete_my_session: response(204), auth_logout: response(204))
    allow(client.auth).to receive(:sign_out_captured).and_wrap_original do |original, *args|
      captured << true
      original.call(*args)
    end
  end

  def refresh_thread
    Thread.new do
      client.auth.refresh_session
    rescue Volcano::Error::VolcanoError => e
      e
    end
  end

  def logout_thread
    Thread.new do
      Thread.current.name = 'logout'
      client.auth.sign_out
    rescue Volcano::Error::VolcanoError => e
      e
    end
  end

  def complete_refresh_and_logout(entered, release, captured)
    refreshing = refresh_thread
    Timeout.timeout(2) { entered.pop }
    signing_out = logout_thread
    Timeout.timeout(2) { captured.pop }
    yield if block_given?
    release << true
    [refreshing, signing_out].map(&:value)
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
    expect(transport).to have_received(:auth_logout)
      .with(authorization: 'anon', refresh_token: 'rotated').once
    expect(transport).to have_received(:auth_refresh).once
    expect(client.current_session).to be_nil
  end

  it 'retains rotated credentials after explicit replacement while logout waits' do
    entered, release, captured = Array.new(3) { Queue.new }
    replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'other')
    stub_refresh_owner(entered, release)
    signal_logout_capture(captured)
    complete_refresh_and_logout(entered, release, captured) { client.auth.current_session = replacement }
    expect(transport).to have_received(:auth_logout)
      .with(authorization: 'anon', refresh_token: 'rotated').once
    expect(transport).to have_received(:auth_refresh).once
    expect(client.current_session).to eq(replacement)
  end

  [401, 403, 429, 503].each do |status|
    it "surfaces joined refresh failure #{status} without claiming replacement" do
      entered, release, captured = Array.new(3) { Queue.new }
      signal_logout_capture(captured)
      allow(transport).to receive(:auth_delete_my_session).and_return(response(401))
      allow(transport).to receive(:auth_refresh) do
        entered << true
        Timeout.timeout(2) { release.pop }
        response(status, 'error' => 'refresh rejected')
      end
      _, error = complete_refresh_and_logout(entered, release, captured)
      expect(error).not_to be_a(Volcano::Error::SessionChangedError)
      expect(error.status).to eq(status)
      expect(client.current_session).to be_nil
      expect(transport).to have_received(:auth_refresh).once
      expect(transport).to have_received(:auth_delete_my_session).once
    end
  end

  it 'revokes a verified pair after joining a throttled refresh' do
    entered, release, captured = Array.new(3) { Queue.new }
    allow(transport).to receive(:auth_signin).and_return(refresh_response(session_a))
    client.auth.sign_in(email: 'u@example.com', password: 'synthetic')
    signal_logout_capture(captured)
    allow(transport).to receive(:auth_refresh) do
      entered << true
      Timeout.timeout(2) { release.pop }
      response(429, 'error' => 'throttled')
    end
    _, outcome = complete_refresh_and_logout(entered, release, captured)
    expect(outcome).to be_nil
    expect(transport).to have_received(:auth_logout).once
    expect(transport).not_to have_received(:auth_delete_my_session)
  end

  def finish_refresh_before_logout_claim(release, refreshing)
    allow(client).to receive(:capture_session_binding).and_wrap_original do |original|
      binding = original.call
      if Thread.current == Thread.main
        release << true
        refreshing.value
      end
      binding
    end
  end

  def stub_first_thread_refresh_failure(entered, release)
    allow(transport).to receive(:auth_refresh) do
      if Thread.current != Thread.main
        entered << true
        Timeout.timeout(2) { release.pop }
      end
      response(401)
    end
  end

  it 'does not call rejected credentials an explicit replacement' do
    entered, release = Array.new(2) { Queue.new }
    stub_first_thread_refresh_failure(entered, release)
    allow(transport).to receive(:auth_delete_my_session).and_return(response(401))
    refreshing = refresh_thread
    Timeout.timeout(2) { entered.pop }
    finish_refresh_before_logout_claim(release, refreshing)
    expect { client.auth.sign_out }.to raise_error(Volcano::Error::AuthenticationError)
    expect(client.current_session).to be_nil
  ensure
    release << true if release.empty?
    refreshing&.join(2)
  end

  context 'with concurrent sign-out calls' do
    let(:signals) { { entered: Queue.new, release: Queue.new, captured: Queue.new } }

    def concurrent_logout_results
      first = logout_thread
      wait_for_logout_signal(:entered)
      signal_second_logout_capture
      second = logout_thread
      wait_for_logout_signal(:captured)
      signals[:release] << true
      [first, second].map { |thread| Timeout.timeout(2) { thread.value } }
    ensure
      finish_logout_threads(first, second)
    end

    def wait_for_logout_signal(name)
      Timeout.timeout(2) { signals.fetch(name).pop }
    end

    def finish_logout_threads(*threads)
      signals[:release] << true if signals[:release].empty?
      threads.compact.each { |thread| thread.join(2) }
    end

    def signal_second_logout_capture
      owner = client.capture_session_binding[1]
      allow(owner).to receive(:result).and_wrap_original do |original, *args|
        signals[:captured] << true
        original.call(*args)
      end
    end

    def pause_logout
      signals[:entered] << true
      Timeout.timeout(2) { signals[:release].pop }
    end

    [204, 503].product([false, true]).each do |status, after_clear|
      context "when revocation returns #{status}, after clear: #{after_clear}" do
        before do
          allow(transport).to receive(:auth_delete_my_session) do
            pause_logout unless after_clear
            response(status, 'error' => 'unavailable')
          end
          if after_clear
            allow(client).to receive(:clear_session_if_current?).and_wrap_original do |original, *args, **kwargs|
              original.call(*args, **kwargs).tap { pause_logout }
            end
          end
        end

        it 'shares the revocation outcome' do
          results = concurrent_logout_results
          if status == 204
            expect(results).to eq([nil, nil])
          else
            expect(results).to all(be_a(Volcano::Error::VolcanoError))
            expect(results.map(&:status)).to eq([status, status])
          end
          expect(transport).to have_received(:auth_delete_my_session).once
          expect(client.current_session).to be_nil
        end
      end
    end
  end

  [false, true].each do |refresh_first|
    it "revokes a server-issued pair without access renewal, preceding429: #{refresh_first}" do
      allow(transport).to receive_messages(auth_signin: refresh_response(session_a), auth_logout: response(204),
                                           auth_delete_my_session: response(401), auth_refresh: response(429))
      issued = client.auth.sign_in(email: 'u@example.com', password: 'synthetic')
      owner = client.capture_session_binding[1]
      expect { client.auth.refresh_session }.to raise_error(Volcano::Error::RateLimitedError) if refresh_first
      client.auth.sign_out
      expect(transport).to have_received(:auth_logout).with(authorization: 'anon', refresh_token: 'rotated').once
      expect(transport).not_to have_received(:auth_delete_my_session)
      expect(owner).not_to be_verified_pair(issued)
    end
  end

  def adopt_supplied_session(session, hosted)
    return client.auth.adopt_hosted_auth_session(session, state: 'nonce', expected_state: 'nonce') if hosted

    client.auth.current_session = session
  end

  [false, true].each do |hosted|
    it "drops server pair provenance on explicit adoption, hosted: #{hosted}" do
      allow(transport).to receive_messages(auth_signin: refresh_response(session_a),
                                           auth_delete_my_session: response(204))
      original = client.auth.sign_in(email: 'u@example.com', password: 'synthetic')
      adopt_supplied_session(Volcano::Session.new(token(session_b), original.refresh_token, 'other'), hosted)
      client.auth.sign_out
      expect(transport).to have_received(:auth_delete_my_session)
        .with(authorization: token(session_b), session_id: session_b).once
    end
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
