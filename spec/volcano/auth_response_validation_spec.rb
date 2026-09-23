# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  def response(payload)
    Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil)
  end

  def valid_session_entry
    { 'id' => 'session', 'user_id' => 'user', 'provider' => 'email', 'expires_at' => Time.utc(2026),
      'is_active' => true, 'is_current' => false }
  end

  def valid_session_page
    { 'sessions' => [valid_session_entry], 'total' => 1, 'page' => 1, 'limit' => 20, 'total_pages' => 1 }
  end

  [nil, [], {}, { 'sessions' => nil }, { 'sessions' => [] }].each do |payload|
    it "rejects an incomplete session page #{payload.inspect}" do
      allow(transport).to receive(:auth_get_my_sessions).and_return(response(payload))

      expect { client.auth.list_sessions }.to raise_error(TypeError, 'Expected a complete session page')
    end
  end

  [nil, {}, 'invalid'].each do |session|
    it "rejects an incomplete session entry #{session.inspect}" do
      allow(transport).to receive(:auth_get_my_sessions).and_return(response({ 'sessions' => [session] }))

      expect { client.auth.list_sessions }.to raise_error(TypeError, 'Expected a complete authentication session')
    end
  end

  { 'id' => 42, 'user_id' => nil, 'provider' => false, 'expires_at' => 'later',
    'is_active' => 1, 'is_current' => nil, 'user_agent' => 3, 'ip_address' => false,
    'last_ip_address' => [], 'last_activity_at' => 'later', 'session_started_at' => 0,
    'created_at' => false, 'updated_at' => {} }.each do |field, invalid|
    it "rejects an invalid session #{field}" do
      entry = valid_session_entry.merge(field => invalid)
      payload = valid_session_page.merge('sessions' => [entry])
      allow(transport).to receive(:auth_get_my_sessions).and_return(response(payload))

      expect { client.auth.list_sessions }.to raise_error(TypeError, 'Expected a complete authentication session')
    end
  end

  %w[total page limit total_pages].each do |field|
    it "rejects an invalid page #{field}" do
      allow(transport).to receive(:auth_get_my_sessions).and_return(response(valid_session_page.merge(field => '1')))

      expect { client.auth.list_sessions }.to raise_error(TypeError, 'Expected a complete session page')
    end
  end

  [nil, {}, { 'providers' => nil }, { 'providers' => [nil] }, { 'providers' => [{}] }].each do |payload|
    it "rejects an incomplete linked-provider response #{payload.inspect}" do
      allow(transport).to receive(:auth_list_oauth_providers).and_return(response(payload))

      expect { client.auth.list_linked_oauth_providers }
        .to raise_error(TypeError, 'Expected complete linked OAuth providers')
    end
  end

  [{ 'provider' => ' ' }, { 'linked_at' => nil }, { 'updated_at' => '2026-01-01' }].each do |fields|
    it "rejects malformed linked-provider fields #{fields.inspect}" do
      provider = { 'provider' => 'github', 'linked_at' => Time.utc(2026), 'updated_at' => Time.utc(2026) }
      payload = { 'providers' => [provider.merge(fields)] }
      allow(transport).to receive(:auth_list_oauth_providers).and_return(response(payload))

      expect { client.auth.list_linked_oauth_providers }
        .to raise_error(TypeError, 'Expected complete linked OAuth providers')
    end
  end

  [nil, {}, { 'authorization_url' => nil }, { 'authorization_url' => 1 },
   { 'authorization_url' => ' ' }].each do |payload|
    it "rejects an invalid OAuth authorization URL #{payload.inspect}" do
      allow(transport).to receive(:auth_link_oauth_provider).and_return(response(payload))

      expect { client.auth.link_oauth_provider('github') }
        .to raise_error(TypeError, 'Expected an OAuth authorization URL')
    end
  end

  [nil, { 'message' => 1 }, { 'new_email' => false }].each do |payload|
    it "rejects an invalid email-change acknowledgement #{payload.inspect}" do
      allow(transport).to receive(:auth_request_email_change).and_return(response(payload))

      expect { client.auth.request_email_change(new_email: 'new@example.com') }
        .to raise_error(TypeError, 'Expected a valid email-change acknowledgement')
    end
  end

  [nil, {}, 'invalid'].each do |payload|
    it "rejects missing OAuth API response data #{payload.inspect}" do
      allow(transport).to receive(:auth_call_oauth_api).and_return(response(payload))

      expect { client.auth.call_oauth_api('github', endpoint: '/user') }
        .to raise_error(TypeError, 'Expected OAuth provider API response data')
    end
  end

  it 'copies and freezes mutable scalar OAuth response data' do
    timestamp = Time.utc(2026, 1, 1)
    allow(transport).to receive(:auth_call_oauth_api).and_return(response({ 'data' => timestamp }))

    result = client.auth.call_oauth_api('github', endpoint: '/user')
    timestamp.localtime('+03:00')

    expect(result).to eq(Time.utc(2026, 1, 1)).and be_frozen
    expect(result).not_to equal(timestamp)
    expect(result.utc_offset).to eq(0)
    expect(timestamp).not_to be_frozen
  end

  %w[banned_until last_sign_in_at created_at updated_at].each do |field|
    it "rejects an impossible RFC3339 timestamp in #{field}" do
      profile = { 'id' => 'user', 'email' => 'user@example.com', 'status' => 'active',
                  field => '2026-99-01T00:00:00Z' }
      allow(transport).to receive(:auth_get_user).and_return(response({ 'user' => profile }))
      original = client.current_session

      expect do
        client.auth.user
      end.to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile')
      expect(client.current_session).to be(original)
    end
  end
end
