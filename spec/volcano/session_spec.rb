# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Session do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:profile) { { 'id' => 'user', 'email' => 'user@example.com', 'user_metadata' => { 'roles' => ['reader'] } } }

  %i[sign_in sign_in_anonymously refresh_session].each do |operation|
    it "retains the local user snapshot after #{operation}" do
      response = Volcano::Transport::Response.new(
        status: operation == :sign_in_anonymously ? 201 : 200,
        body: { 'access_token' => 'access', 'refresh_token' => 'refresh', 'user' => profile },
        headers: {}, data: nil
      )
      allow(transport).to receive_messages(auth_signin: response, auth_signup_anonymous: response,
                                           auth_refresh: response)
      client.auth.current_session = described_class.new(access_token: 'old', refresh_token: 'old-refresh',
                                                        user_id: 'user')

      session = if operation == :sign_in
                  client.auth.sign_in(email: 'user@example.com', password: 'secret')
                else
                  client.auth.public_send(operation)
                end

      expect(session.user).to eq(profile).and be_frozen
      expect(session.user['user_metadata']['roles']).to be_frozen
      expect(client.current_session).to equal(session)
    end
  end

  it 'copies nested user data when adopting a session' do
    session = described_class.new(access_token: 'access', refresh_token: 'refresh', user_id: 'user', user: profile)
    profile['user_metadata']['roles'] << 'admin'

    client.auth.current_session = session

    expect(client.current_session).not_to equal(session)
    expect(client.current_session.user['user_metadata']['roles']).to eq(['reader']).and be_frozen
  end

  it 'rejects a snapshot for a different user' do
    session = described_class.new(access_token: 'access', refresh_token: 'refresh', user_id: 'other', user: profile)

    expect { client.auth.current_session = session }.to raise_error(ArgumentError, /complete Volcano::Session/)
    expect(client.current_session).to be_nil
  end

  it 'preserves positional construction of the original three fields' do
    expect(described_class.new('access', 'refresh', 'user').user).to be_nil
  end
end
