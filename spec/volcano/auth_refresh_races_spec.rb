# frozen_string_literal: true

require 'timeout'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:entered) { Queue.new }
  let(:release) { Queue.new }
  let(:captured) { Queue.new }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def session_response(access_token, refresh_token)
    response(200, 'access_token' => access_token, 'refresh_token' => refresh_token,
                  'user' => { 'id' => 'user', 'email' => 'user@example.com', 'status' => 'active' })
  end

  def wait_for(signal)
    Timeout.timeout(2) { signal.pop }
  end

  def in_thread(operation)
    Thread.new do
      client.auth.public_send(operation)
    rescue Volcano::Error::VolcanoError => e
      e
    end
  end

  before do
    allow(transport).to receive(:auth_signin).and_return(session_response('opaque-access', 'refresh'))
    client.auth.sign_in(email: 'user@example.com', password: 'synthetic')
  end

  it 'reuses a completed rotation when an earlier caller has not yet claimed refresh ownership' do
    owner = client.capture_session_binding[1]
    pause_background_claim(owner)
    allow(transport).to receive(:auth_refresh).and_return(session_response('rotated-access', 'rotated-refresh'))
    delayed = in_thread(:refresh_session)
    wait_for(entered)
    rotated = client.auth.refresh_session
    release << true

    expect(Timeout.timeout(2) { delayed.value }).to be(rotated)
    expect(client.current_session).to be(rotated)
    expect(transport).to have_received(:auth_refresh).with(authorization: 'anon', refresh_token: 'refresh').once
  ensure
    delayed&.kill&.join
  end

  def pause_background_claim(owner)
    allow(owner).to receive(:refresh).and_wrap_original do |original, &operation|
      unless Thread.current == Thread.main
        entered << true
        wait_for(release)
      end
      original.call(&operation)
    end
  end

  it 'surfaces a joined refresh failure without revoking an unverified opaque credential pair' do
    pause_failing_refresh
    signal_sign_out_capture
    refreshing = in_thread(:refresh_session)
    wait_for(entered)
    signing_out = in_thread(:sign_out)
    wait_for(captured)
    release << true
    outcome = Timeout.timeout(2) { signing_out.value }

    expect(outcome).to be_a(Volcano::Error::VolcanoError).and have_attributes(status: 503)
    expect(client.current_session).to be_nil
    expect(transport).to have_received(:auth_refresh).once
    expect(transport).not_to have_received(:auth_logout)
    expect(transport).not_to have_received(:auth_delete_my_session)
  ensure
    [refreshing, signing_out].compact.each { |thread| thread.kill.join }
  end

  def pause_failing_refresh
    allow(transport).to receive(:auth_refresh) do
      entered << true
      wait_for(release)
      response(503, 'error' => 'refresh unavailable')
    end
  end

  def signal_sign_out_capture
    allow(transport).to receive_messages(auth_logout: response(204, nil), auth_delete_my_session: response(204, nil))
    allow(client.auth).to receive(:sign_out_captured).and_wrap_original do |original, *args|
      captured << true
      original.call(*args)
    end
  end
end
