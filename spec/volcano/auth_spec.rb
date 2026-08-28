# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Auth do
  describe 'public auth values and client state' do
    let(:client) do
      Volcano::Client.new(
        anon_key: 'anon-key',
        access_token: 'access-token',
        refresh_token: 'refresh-token',
        _transport: Object.new
      )
    end

    it 'bootstraps a partial session without inventing a user' do
      expect(client.current_session).to eq(
        Volcano::Session.new(access_token: 'access-token', refresh_token: 'refresh-token')
      )
      expect(client.current_user).to be_nil
    end

    it 'accepts an access token without a refresh token' do
      partial = Volcano::Client.new(anon_key: 'anon-key', access_token: 'access-token', _transport: Object.new)

      expect(partial.current_session.refresh_token).to be_nil
    end

    it 'rejects a refresh token without an access token' do
      expect do
        Volcano::Client.new(anon_key: 'anon-key', refresh_token: 'refresh-token', _transport: Object.new)
      end.to raise_error(ArgumentError, /refresh token requires an access token/i)
    end

    it 'commits and clears user and session state atomically' do
      user = Volcano::User.new(id: 'user-id', email: 'user@example.com')
      session = Volcano::Session.new(access_token: 'next-access', refresh_token: 'next-refresh', user_id: 'user-id')

      client.commit_auth(session, user)
      expect([client.current_session, client.current_user]).to eq([session, user])

      client.clear_auth
      expect([client.current_session, client.current_user]).to eq([nil, nil])
    end

    it 'stores a user without replacing the session' do
      session = client.current_session
      user = Volcano::User.new(id: 'user-id', email: 'user@example.com')

      client.store_user(user)

      expect(client.current_session).to be(session)
      expect(client.current_user).to be(user)
    end

    it 'freezes nested metadata and redacts secret-bearing values' do
      metadata = { 'nested' => [{ 'value' => 'kept' }] }
      user = Volcano::User.new(id: 'user-id', email: 'user@example.com', user_metadata: metadata)
      values = [
        client.current_session,
        Volcano::EmailChangeResult.new(
          message: 'sent', new_email: 'next@example.com', email_change_token: 'email-secret'
        ),
        Volcano::AuthorizationRequest.new(authorization_url: 'https://secret.example', state: 'state-secret')
      ]

      expect { user.user_metadata['nested'][0]['value'] = 'changed' }.to raise_error(FrozenError)
      secrets = /access-token|refresh-token|email-secret|secret\.example|state-secret/
      expect(values.map(&:inspect).join).not_to match(secrets)
    end

    it 'exports immutable public authentication values' do
      values = [
        Volcano::SignUpResult.new(confirmation_required: true, message: 'sent'),
        Volcano::MessageResult.new(message: 'sent'),
        Volcano::OAuthProvider.new(provider: 'github'),
        Volcano::OAuthTokenResult.new(provider: 'github'),
        Volcano::AuthSession.new(
          id: 'session-id', user_id: 'user-id', provider: 'password',
          expires_at: Time.utc(2026), is_active: true, is_current: true
        ),
        Volcano::SessionPage.new
      ]

      expect(values).to all(be_frozen)
    end
  end
end
