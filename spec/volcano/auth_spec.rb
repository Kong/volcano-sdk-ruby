# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:profile) do
    { 'id' => 'user', 'email' => 'updated@example.com', 'status' => 'active',
      'user_metadata' => { 'roles' => ['editor'] }, 'created_at' => '2026-09-01T00:00:00Z' }
  end
  let(:response) { Volcano::Transport::Response.new(status: 200, body: { 'user' => profile }, headers: {}, data: nil) }

  before do
    client.auth.current_session = Volcano::Session.new(
      access_token: 'access', refresh_token: 'refresh', user_id: 'user',
      user: { 'id' => 'user', 'email' => 'old@example.com' }
    )
  end

  {
    user: [:auth_get_user, {}],
    update_user: [:auth_update_user, { metadata: { 'roles' => ['editor'] } }],
    convert_anonymous: [:auth_convert_anonymous, { email: 'updated@example.com', password: 'secret' }],
    confirm_email_change: [:auth_confirm_email_change, { token: 'confirmation' }]
  }.each do |operation, (transport_method, arguments)|
    describe "##{operation}" do
      before { allow(transport).to receive(transport_method).and_return(response) }

      it 'caches the returned profile without changing credentials or session binding' do
        generation, lineage, previous = client.capture_session_binding
        user = client.auth.public_send(operation, **arguments)
        current = client.current_session

        expect(user).to be_a(Volcano::User)
        expect(user.created_at).to be_a(Time)
        expect(current.user).to eq(profile).and be_frozen
        expect(current.to_h.except(:user)).to eq(previous.to_h.except(:user))
        expect(client.capture_session_binding.first(2)).to eq([generation, lineage])
      end

      it 'owns the snapshot and preserves previously returned sessions' do
        previous = client.current_session
        client.auth.public_send(operation, **arguments)
        profile['user_metadata']['roles'] << 'admin'

        expect(client.current_session.user['user_metadata']['roles']).to eq(['editor']).and be_frozen
        expect(previous.user['email']).to eq('old@example.com')
      end

      it 'does not emit an authentication-state event for profile updates' do
        events = []
        subscription = client.auth.on_auth_state_change { |event, _session| events << event }
        client.auth.public_send(operation, **arguments)

        expect(events).to eq([:initial_session])
        subscription.unsubscribe
      end

      it 'rejects a different user without replacing the snapshot' do
        previous = client.current_session
        profile['id'] = 'other'

        expect { client.auth.public_send(operation, **arguments) }
          .to raise_error(Volcano::Error::AuthenticationError, /different user/)
        expect(client.current_session).to equal(previous)
      end

      it 'rejects an invalid profile without replacing the snapshot' do
        previous = client.current_session
        profile.delete('status')

        expect { client.auth.public_send(operation, **arguments) }
          .to raise_error(Volcano::Error::AuthenticationError, /complete user profile/)
        expect(client.current_session).to equal(previous)
      end

      it 'preserves a replacement session when the response arrives late' do
        replacement = Volcano::Session.new('new-access', 'new-refresh', 'new-user')
        allow(transport).to receive(transport_method) do
          client.auth.current_session = replacement
          response
        end

        expect { client.auth.public_send(operation, **arguments) }.to raise_error(Volcano::Error::SessionChangedError)
        expect(client.current_session).to eq(replacement)
      end

      it 'does not restore a session cleared while the request was in flight' do
        allow(transport).to receive(transport_method) do
          client.store_session(nil)
          response
        end

        expect { client.auth.public_send(operation, **arguments) }.to raise_error(Volcano::Error::SessionChangedError)
        expect(client.current_session).to be_nil
      end
    end
  end
end
