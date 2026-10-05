# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }
  let(:profile) { { 'id' => 'user', 'email' => 'user@example.com', 'status' => 'active' } }

  def response(payload)
    Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil)
  end

  [nil, { 'user' => nil }, { 'user' => { id: 'user' } },
   { 'user' => { 'id' => 'user', 'extra' => Object.new } },
   { 'user' => { 'id' => 'user', 'extra' => Float::NAN } }].each do |payload|
    it "rejects a non-JSON profile response #{payload.inspect}" do
      allow(transport).to receive(:auth_get_user).and_return(response(payload))
      original_session = client.current_session

      expect { client.auth.user }
        .to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile')
      expect(client.current_session).to equal(original_session)
    end
  end

  { 'id' => 0, 'email' => false, 'status' => 'unknown', 'project_id' => 7,
    'email_confirmed' => 7, 'user_metadata' => [], 'avatar_url' => 7,
    'created_at' => '2026-01-01' }.each do |field, value|
    it "rejects invalid #{field} without updating the cached session" do
      allow(transport).to receive(:auth_get_user).and_return(response({ 'user' => profile.merge(field => value) }))
      original_session = client.current_session

      expect { client.auth.user }
        .to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile')
      expect(client.current_session).to equal(original_session)
    end
  end

  it 'preserves nested JSON and false values in the returned user and session snapshot' do
    metadata = { 'roles' => ['admin', { 'enabled' => false, 'count' => 3, 'ratio' => 0.5 }] }
    wire = profile.merge('email_confirmed' => false, 'app_metadata' => metadata)
    allow(transport).to receive(:auth_get_user).and_return(response({ 'user' => wire }))

    user = client.auth.user
    metadata['roles'].clear

    expect(user.email_confirmed).to be(false)
    expect(user.app_metadata).to eq({ 'roles' => ['admin', { 'enabled' => false, 'count' => 3, 'ratio' => 0.5 }] })
    expect(client.current_session.user).to include('app_metadata' => user.app_metadata)
  end

  it 'preserves arbitrary printable metadata strings across profile reads' do
    check_property(PropCheck::Generators.printable_string) do |value|
      wire = profile.merge('user_metadata' => { 'note' => value })
      allow(transport).to receive(:auth_get_user).and_return(response({ 'user' => wire }))

      expect(client.auth.user.user_metadata).to eq({ 'note' => value })
      expect(client.current_session.user).to include('user_metadata' => { 'note' => value })
    end
  end
end
