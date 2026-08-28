# frozen_string_literal: true

require 'pp'
require 'spec_helper'

AuthSpecResponse = Volcano::Transport::Response
AUTH_SPEC_USER_PAYLOAD = {
  'id' => 'user-id',
  'email' => 'user@example.com',
  'project_id' => 'project-id',
  'email_confirmed' => true,
  'user_metadata' => { 'plan' => 'starter' },
  'app_metadata' => { 'role' => 'developer' },
  'status' => 'active',
  'created_at' => '2026-08-28T12:00:00Z'
}.freeze

class AuthSpecTransport
  attr_reader :calls

  def initialize
    @calls = []
    @responses = Hash.new { |responses, operation| responses[operation] = [] }
  end

  def queue(operation, status, body = nil, headers = {})
    @responses[operation] << AuthSpecResponse.new(status:, body:, headers:, data: nil)
  end

  def queue_error(operation, error)
    @responses[operation] << error
  end

  def method_missing(operation, **arguments)
    return super unless operation.to_s.match?(/\A(?:auth_|refresh_oauth|get_oauth|call_oauth)/)

    @calls << [operation, arguments]
    response = @responses.fetch(operation).shift || raise("no response queued for #{operation}")
    raise response if response.is_a?(Exception)

    response
  end

  def respond_to_missing?(operation, include_private = false)
    operation.to_s.match?(/\A(?:auth_|refresh_oauth|get_oauth|call_oauth)/) || super
  end
end

class SerialRefreshTransport
  attr_reader :calls

  def initialize
    @calls = Queue.new
    @release = Queue.new
  end

  def auth_refresh(authorization:, refresh_token:)
    @calls << [authorization, refresh_token]
    @release.pop if refresh_token == 'old-refresh'
    suffix = refresh_token == 'old-refresh' ? 'next' : 'final'
    AuthSpecResponse.new(
      status: 200,
      body: {
        'access_token' => "#{suffix}-access",
        'refresh_token' => "#{suffix}-refresh",
        'expires_in' => 3600,
        'user' => AUTH_SPEC_USER_PAYLOAD
      },
      headers: {}, data: nil
    )
  end

  def release
    @release << true
  end
end

class BlockingAuthTransport < AuthSpecTransport
  attr_reader :entered

  def initialize(operation, response)
    super()
    @operation = operation
    @response = response
    @entered = Queue.new
    @release = Queue.new
  end

  def method_missing(operation, **arguments)
    return super unless operation == @operation

    @calls << [operation, arguments]
    @entered << true
    @release.pop
    @response
  end

  def respond_to_missing?(operation, include_private = false)
    operation == @operation || super
  end

  def release = @release << true
end

RSpec.describe Volcano::Auth do
  def token_payload(access: 'access-token', refresh: 'refresh-token')
    {
      'access_token' => access,
      'refresh_token' => refresh,
      'expires_in' => 3600,
      'user' => AUTH_SPEC_USER_PAYLOAD
    }
  end

  def authenticated_client(transport)
    Volcano::Client.new(
      anon_key: 'anon-key', access_token: 'access-token', refresh_token: 'refresh-token', _transport: transport
    )
  end

  def current_auth_session
    {
      'id' => 'session-id', 'user_id' => 'user-id', 'provider' => 'password',
      'expires_at' => Time.utc(2026, 8, 29, 12), 'is_active' => true, 'is_current' => true
    }
  end

  def blocking_auth_transport(operation, body)
    response = AuthSpecResponse.new(status: 200, body:, headers: {}, data: nil)
    BlockingAuthTransport.new(operation, response)
  end

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

    it 'exposes an immutable API URL' do
      expect(client.api_url).to be_frozen
      expect { client.api_url << '/v2' }.to raise_error(FrozenError)
    end

    it 'rejects a refresh token without an access token' do
      expect do
        Volcano::Client.new(anon_key: 'anon-key', refresh_token: 'refresh-token', _transport: Object.new)
      end.to raise_error(ArgumentError, /refresh token requires an access token/i)
    end

    it 'redacts secrets from inspect and string conversion' do
      session = Volcano::Session.new(access_token: 'access', refresh_token: 'refresh')
      authorization = Volcano::AuthorizationRequest.new(
        authorization_url: 'https://secret', state: 'generated-state'
      )

      expect([session.inspect, session.to_s].join).not_to include('access', 'refresh')
      expect([authorization.inspect, authorization.to_s].join).not_to include('https://secret', 'generated-state')
    end

    it 'copies and freezes caller-owned session strings' do
      access_token = +'access-token'
      session = Volcano::Session.new(access_token:)
      access_token.clear

      expect(session.access_token).to eq('access-token')
      expect(session.access_token).to be_frozen
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

    it 'replaces legacy session state through the coordinated auth transition' do
      user = Volcano::User.new(id: 'user-id', email: 'user@example.com')
      replacement = Volcano::Session.new(access_token: 'replacement-access')
      client.commit_auth(client.current_session, user)
      events = []
      client.auth.on_auth_state_change { |current_user| events << current_user }

      client.store_session(replacement)

      expect([client.current_session, client.current_user]).to eq([replacement, nil])
      expect(events).to eq([user, nil])
    end

    it 'invokes initial auth listeners without holding the state monitor' do
      client.commit_auth(client.current_session, Volcano::User.new(id: 'user-id', email: 'user@example.com'))
      outcome = Queue.new
      first_notification = true

      client.auth.on_auth_state_change do
        next unless first_notification

        first_notification = false
        worker = Thread.new { client.commit_auth(client.current_session, client.current_user) }
        outcome << (worker.join(0.2) ? :completed : :blocked)
      end

      expect(outcome.pop).to eq(:completed)
    end

    it 'freezes nested metadata and redacts secret-bearing values' do
      metadata = { 'nested' => [{ 'value' => 'kept' }] }
      user = Volcano::User.new(id: 'user-id', email: 'user@example.com', user_metadata: metadata)
      values = [
        client.current_session,
        Volcano::SignUpResult.new(
          confirmation_required: false, message: 'created', session: client.current_session
        ),
        Volcano::EmailChangeResult.new(
          message: 'sent', new_email: 'next@example.com', email_change_token: 'email-secret'
        ),
        Volcano::AuthorizationRequest.new(authorization_url: 'https://secret.example', state: 'state-secret')
      ]

      expect { user.user_metadata['nested'][0]['value'] = 'changed' }.to raise_error(FrozenError)
      secrets = /access-token|refresh-token|email-secret|secret\.example|state-secret/
      rendered = values.flat_map { |value| [value.inspect, value.pretty_inspect] }.join
      expect(rendered).not_to match(secrets)
    end

    it 'exports immutable public authentication values' do
      session_id = +'session-id'
      expires_at = Time.utc(2026)
      auth_session = Volcano::AuthSession.new(
        id: session_id, user_id: 'user-id', provider: 'password',
        expires_at:, is_active: true, is_current: true
      )
      values = [
        Volcano::SignUpResult.new(confirmation_required: true, message: 'sent'),
        Volcano::MessageResult.new(message: 'sent'),
        Volcano::OAuthProvider.new(provider: 'github'),
        Volcano::OAuthTokenResult.new(provider: 'github'),
        auth_session,
        Volcano::SessionPage.new
      ]
      session_id.clear

      expect(values).to all(be_frozen)
      expect([auth_session.id, auth_session.expires_at.frozen?]).to eq(['session-id', true])
    end
  end

  describe 'session lifecycle' do
    let(:transport) { AuthSpecTransport.new }
    let(:client) { Volcano::Client.new(anon_key: 'anon-key', _transport: transport) }

    it 'signs up without inventing a session and can opt into immediate sign-in' do
      transport.queue(:auth_signup, 201, 'confirmation_required' => true, 'message' => 'Check email')
      result = client.auth.sign_up(email: 'user@example.com', password: 'password')

      expect(result).to eq(Volcano::SignUpResult.new(confirmation_required: true, message: 'Check email'))
      expect(client.current_session).to be_nil

      transport.queue(:auth_signup, 201, 'confirmation_required' => false, 'message' => 'Created')
      transport.queue(:auth_signin, 200, token_payload)
      signed_in = client.auth.sign_up(email: 'user@example.com', password: 'password', sign_in: true)
      expect([signed_in.user, signed_in.session]).to eq([client.current_user, client.current_session])
    end

    it 'rejects malformed signup acknowledgements' do
      malformed = [
        {},
        { 'confirmation_required' => false },
        { 'confirmation_required' => 'false', 'message' => 'Created' },
        { 'confirmation_required' => false, 'message' => nil }
      ]

      malformed.each do |payload|
        transport.queue(:auth_signup, 201, payload)
        expect { client.auth.sign_up(email: 'user@example.com', password: 'password') }.to raise_error(
          Volcano::Error::AuthenticationError, 'Invalid authentication response'
        )
      end
    end

    it 'commits sign-in state before listeners observe it' do
      observations = []
      client.auth.on_auth_state_change do |user|
        observations << [client.current_session, client.current_user, user]
      end
      transport.queue(:auth_signin, 200, token_payload)

      session = client.auth.sign_in(email: 'user@example.com', password: 'password')

      expect(session.user_id).to eq('user-id')
      expect(client.current_user.email).to eq('user@example.com')
      expect(observations.first).to eq([nil, nil, nil])
      expect(observations.last).to eq([session, client.current_user, client.current_user])
    end

    it 'preserves auth event order across reentrant transitions' do
      events = []
      client.auth.on_auth_state_change do |user|
        events << [:first, user&.id]
        client.clear_auth if user
      end
      client.auth.on_auth_state_change { |user| events << [:second, user&.id] }
      events.clear
      transport.queue(:auth_signin, 200, token_payload)

      client.auth.sign_in(email: 'user@example.com', password: 'password')

      expect(events).to eq([[:first, 'user-id'], [:second, 'user-id'], [:first, nil], [:second, nil]])
      expect(client.current_session).to be_nil
    end

    it 'retrieves and updates the user without replacing the session' do
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'access-token', refresh_token: 'refresh-token', _transport: transport
      )
      session = session_client.current_session
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)
      updated_payload = AUTH_SPEC_USER_PAYLOAD.merge('email' => 'updated@example.com')
      transport.queue(:auth_update_user, 200, 'user' => updated_payload)

      expect(session_client.auth.get_user.email).to eq('user@example.com')
      expect(session_client.auth.update_user(user_metadata: { 'plan' => 'pro' }).email).to eq('updated@example.com')
      expect(session_client.current_session).to be(session)
    end

    it 'rotates tokens and refreshes an authenticated request once after 401' do
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'old-access', refresh_token: 'old-refresh', _transport: transport
      )
      transport.queue(:auth_get_user, 401, 'error' => 'expired')
      transport.queue(:auth_refresh, 200, token_payload(access: 'new-access', refresh: 'new-refresh'))
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)

      expect(session_client.auth.get_user.id).to eq('user-id')
      expect(session_client.current_session.access_token).to eq('new-access')
      expect(transport.calls.map(&:first)).to eq(%i[auth_get_user auth_refresh auth_get_user])
    end

    it 'clears stale state when refresh fails' do
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'old-access', refresh_token: 'old-refresh', _transport: transport
      )
      transport.queue(:auth_refresh, 401, 'error' => 'refresh expired')

      expect { session_client.auth.refresh_session }.to raise_error(Volcano::Error::AuthenticationError)
      expect([session_client.current_session, session_client.current_user]).to eq([nil, nil])
    end

    it 'does not repeat signed-out notification on refresh without local auth' do
      events = []
      client.auth.on_auth_state_change { |user| events << user }
      events.clear

      expect { client.auth.refresh_session }.to raise_error(Volcano::Error::AuthenticationError)
      expect(events).to be_empty
    end

    it 'clears rotated auth when the post-refresh retry is unauthorized' do
      session_client = authenticated_client(transport)
      transport.queue(:auth_get_user, 401, 'error' => 'expired')
      transport.queue(
        :auth_refresh, 200,
        token_payload(access: 'rotated-access', refresh: 'rotated-refresh')
      )
      transport.queue(:auth_get_user, 401, 'error' => 'revoked rotated-access rotated-refresh')

      expect { session_client.auth.get_user }.to raise_error(
        Volcano::Error::AuthenticationError, 'revoked [REDACTED] [REDACTED]'
      )
      expect(session_client.current_session).to be_nil
    end

    it 'serializes concurrent refresh-token rotation' do
      serial_transport = SerialRefreshTransport.new
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'old-access', refresh_token: 'old-refresh',
        _transport: serial_transport
      )
      first = Thread.new { session_client.auth.refresh_session }
      expect(serial_transport.calls.pop).to eq(%w[anon-key old-refresh])
      second = Thread.new { session_client.auth.refresh_session }
      Timeout.timeout(1) { Thread.pass until second.status == 'sleep' }

      expect(serial_transport.calls).to be_empty
      serial_transport.release
      expect([first.value.refresh_token, second.value.refresh_token]).to eq(%w[next-refresh final-refresh])
    end

    it 'redacts transport causes and credentials rotated during retry' do
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'old-access', refresh_token: 'old-refresh', _transport: transport
      )
      transport.queue(:auth_get_user, 401, 'error' => 'expired')
      transport.queue(:auth_refresh, 200, token_payload(access: 'new-access', refresh: 'new-refresh'))
      transport.queue_error(:auth_get_user, IOError.new('new-access new-refresh'))

      expect { session_client.auth.get_user }.to raise_error do |error|
        expect(error.message).to eq('[REDACTED] [REDACTED]')
        expect(error.cause).to be_nil
      end
    end

    it 'redacts the anonymous key from authentication transport failures' do
      transport.queue_error(:auth_signin, IOError.new('anon-key password'))

      expect { client.auth.sign_in(email: 'user@example.com', password: 'password') }.to raise_error do |error|
        expect(error.message).to eq('[REDACTED] [REDACTED]')
        expect(error.cause).to be_nil
      end
    end

    it 'always clears sign-out state and isolates listener failures' do
      session_client = Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'access', refresh_token: 'refresh', _transport: transport
      )
      events = []
      session_client.auth.on_auth_state_change { raise 'listener secret' }
      unsubscribe = session_client.auth.on_auth_state_change { |user| events << user }
      transport.queue(:auth_logout, 500, 'error' => 'failed')

      expect { session_client.auth.sign_out }.to raise_error(Volcano::Error::ServerError)
      expect(session_client.current_session).to be_nil
      expect(events.last).to be_nil
      unsubscribe.call
      expect { unsubscribe.call }.not_to raise_error
    end

    it 'returns nil after a successful sign-out' do
      session_client = authenticated_client(transport)
      transport.queue(:auth_logout, 204)

      expect(session_client.auth.sign_out).to be_nil
      expect(session_client.current_session).to be_nil
    end

    it 'does not repeat signed-out notification on sign-out without local auth' do
      events = []
      client.auth.on_auth_state_change { |user| events << user }
      events.clear

      expect(client.auth.sign_out).to be_nil
      expect(events).to be_empty
    end
  end

  describe 'account, OAuth, and device-session flows' do
    let(:transport) { AuthSpecTransport.new }
    let(:client) do
      Volcano::Client.new(
        anon_key: 'anon-key', access_token: 'access-token', refresh_token: 'refresh-token', _transport: transport
      )
    end

    it 'supports anonymous conversion and email workflows' do
      transport.queue(:auth_signup_anonymous, 201, token_payload)
      transport.queue(:auth_convert_anonymous, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)
      transport.queue(
        :auth_refresh, 200,
        token_payload(access: 'converted-access', refresh: 'converted-refresh')
      )
      transport.queue(:auth_confirm_email, 200, 'message' => 'confirmed')
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)
      transport.queue(:auth_resend_confirmation, 200, 'message' => 'resent')
      transport.queue(:auth_forgot_password, 200, 'message' => 'sent')

      results = [
        client.auth.sign_up_anonymous.user_id,
        client.auth.convert_anonymous(email: 'user@example.com', password: 'password').id,
        client.auth.confirm_email(token: 'token').message,
        client.auth.resend_confirmation(email: 'user@example.com').message,
        client.auth.forgot_password(email: 'user@example.com').message
      ]
      expect(results).to eq(%w[user-id user-id confirmed resent sent])
      expect(client.current_session.access_token).to eq('converted-access')
    end

    it 'preserves confirmation success when the profile refresh fails' do
      transport.queue(:auth_confirm_email, 200, 'message' => 'confirmed')
      transport.queue(:auth_get_user, 503, 'error' => 'temporarily unavailable')

      expect(client.auth.confirm_email(token: 'token').message).to eq('confirmed')
    end

    it 'clears a current session revoked by password reset' do
      transport.queue(:auth_reset_password, 200, 'message' => 'reset')
      transport.queue(:auth_get_user, 401, 'error' => 'expired')
      transport.queue(:auth_refresh, 401, 'error' => 'refresh expired')

      expect(client.auth.reset_password(token: 'token', new_password: 'next').message).to eq('reset')
      expect(client.current_session).to be_nil
    end

    it 'preserves an unrelated current session after password reset' do
      transport.queue(:auth_reset_password, 200, 'message' => 'reset')
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)

      expect(client.auth.reset_password(token: 'token', new_password: 'next').message).to eq('reset')
      expect(client.current_session.access_token).to eq('access-token')
    end

    it 'defers the restored-session listener until user hydration' do
      observations = []
      client.auth.on_auth_state_change { |user| observations << user }
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)

      expect(observations).to be_empty
      user = client.auth.get_user
      expect(observations).to eq([user])
    end

    it 'allows a listener to register another listener during notification' do
      nested_unsubscribers = []
      client.auth.on_auth_state_change do
        nested_unsubscribers << client.auth.on_auth_state_change { nil }
      end
      transport.queue(:auth_get_user, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)

      client.auth.get_user

      expect(nested_unsubscribers.length).to eq(1)
      expect { nested_unsubscribers.first.call }.not_to raise_error
    end

    it 'preserves anonymous conversion success when session refresh fails' do
      transport.queue(:auth_convert_anonymous, 200, 'user' => AUTH_SPEC_USER_PAYLOAD)
      transport.queue(:auth_refresh, 503, 'error' => 'temporarily unavailable')

      converted = client.auth.convert_anonymous(email: 'user@example.com', password: 'password')

      expect(converted.id).to eq('user-id')
      expect(client.current_session).to be_nil
    end

    it 'serializes anonymous conversion with replacement sign-in' do
      serial = blocking_auth_transport(:auth_convert_anonymous, 'user' => AUTH_SPEC_USER_PAYLOAD)
      serial.queue(:auth_refresh, 200, token_payload(access: 'converted-access'))
      serial.queue(:auth_signin, 200, token_payload(access: 'replacement-access'))
      session_client = authenticated_client(serial)
      conversion = Thread.new do
        session_client.auth.convert_anonymous(email: 'converted@example.com', password: 'password')
      end
      serial.entered.pop
      sign_in = Thread.new { session_client.auth.sign_in(email: 'next@example.com', password: 'password') }
      Timeout.timeout(1) { Thread.pass until sign_in.status == 'sleep' }
      serial.release

      expect(
        [conversion.value.id, sign_in.value.access_token, session_client.current_session.access_token]
      ).to eq(%w[user-id replacement-access replacement-access])
    end

    it 'supports the complete email-change lifecycle' do
      transport.queue(
        :auth_request_email_change, 200,
        'message' => 'sent', 'new_email' => 'next@example.com', 'email_change_token' => 'development-token'
      )
      transport.queue(
        :auth_confirm_email_change, 200,
        'message' => 'changed', 'user' => AUTH_SPEC_USER_PAYLOAD.merge('email' => 'next@example.com')
      )
      transport.queue(:auth_cancel_email_change, 200, 'message' => 'cancelled')

      result = client.auth.request_email_change(new_email: 'next@example.com')
      expect(result.inspect).not_to include('development-token')
      confirmation = client.auth.confirm_email_change(token: 'token')
      cancellation = client.auth.cancel_email_change
      expect(
        [result.new_email, confirmation.message, client.current_user.email, cancellation.message]
      ).to eq(%w[next@example.com changed next@example.com cancelled])
    end

    it 'serializes email-change confirmation with replacement sign-in' do
      response = AuthSpecResponse.new(
        status: 200, body: { 'message' => 'changed', 'user' => AUTH_SPEC_USER_PAYLOAD }, headers: {}, data: nil
      )
      serial = BlockingAuthTransport.new(:auth_confirm_email_change, response)
      serial.queue(:auth_signin, 200, token_payload(access: 'replacement-access'))
      session_client = Volcano::Client.new(anon_key: 'anon-key', access_token: 'old-access', _transport: serial)
      confirmation = Thread.new { session_client.auth.confirm_email_change(token: 'token') }
      serial.entered.pop
      sign_in = Thread.new { session_client.auth.sign_in(email: 'next@example.com', password: 'password') }
      Timeout.timeout(1) { Thread.pass until sign_in.status == 'sleep' }
      serial.release

      expect(confirmation.value.message).to eq('changed')
      expect(sign_in.value.access_token).to eq('replacement-access')
      expect(session_client.current_user.email).to eq('user@example.com')
    end

    it 'builds hosted and OAuth authorization requests and validates callback state' do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('generated-state')
      transport.queue(:auth_oauth_authorize, 307, nil, 'Location' => 'https://github.test/authorize')
      transport.queue(:auth_oauth_exchange, 200, token_payload)

      hosted = client.auth.get_hosted_auth_url(project_id: 'project/id', action: 'login')
      oauth = client.auth.get_oauth_authorization_url(provider: 'github', redirect_url: 'https://app.test/callback')
      expect(hosted.authorization_url).to include('/projects/project%2Fid/auth/hosted')
      expect do
        client.auth.exchange_oauth_code(
          code: 'code', redirect_url: 'https://app.test/callback', state: 'wrong', expected_state: oauth.state
        )
      end.to raise_error(Volcano::Error::ValidationError)
      expect do
        client.auth.exchange_oauth_code(
          code: 'code', redirect_url: 'https://app.test/callback', state: nil, expected_state: oauth.state
        )
      end.to raise_error(Volcano::Error::ValidationError)
      expect(client.auth.exchange_oauth_code(
               code: 'code', redirect_url: 'https://app.test/callback', state: oauth.state, expected_state: oauth.state
             )).to eq(client.current_session)
    end

    it 'links providers and exposes provider API results' do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('generated-state')
      transport.queue(:auth_link_oauth_provider, 200, 'authorization_url' => 'https://github.test/link')
      transport.queue(:auth_list_oauth_providers, 200, 'providers' => [{ 'provider' => 'github' }])
      transport.queue(:refresh_oauth_provider_token, 200, 'provider' => 'github', 'message' => 'refreshed')
      transport.queue(:get_oauth_provider_token, 200, 'provider' => 'github', 'expires_in' => 3600)
      transport.queue(:call_oauth_provider_api, 200, 'login' => 'volcano')
      transport.queue(:auth_unlink_oauth_provider, 204)

      results = [
        client.auth.link_oauth_provider(provider: 'github', redirect_url: 'https://app.test/link').state,
        client.auth.get_linked_oauth_providers.map(&:provider),
        client.auth.refresh_oauth_token(provider: 'github').message,
        client.auth.get_oauth_provider_token(provider: 'github').expires_in,
        client.auth.call_oauth_api(provider: 'github', endpoint: '/user'),
        client.auth.unlink_oauth_provider(provider: 'github')
      ]
      expect(results).to eq(
        ['generated-state', ['github'], 'refreshed', 3600, { 'login' => 'volcano' }, nil]
      )
    end

    it 'preserves auth for structured provider-level unauthorized responses' do
      transport.queue(
        :call_oauth_provider_api, 401,
        'error' => 'provider unavailable', 'code' => 'provider_not_linked'
      )

      expect do
        client.auth.call_oauth_api(provider: 'github', endpoint: '/user')
      end.to raise_error(Volcano::Error::AuthenticationError, 'provider unavailable')
      expect(client.current_session.access_token).to eq('access-token')
    end

    it 'preserves schema-valid provider errors without the optional code' do
      transport.queue(
        :call_oauth_provider_api, 401,
        'error' => 'provider is not linked'
      )

      expect do
        client.auth.call_oauth_api(provider: 'github', endpoint: '/user')
      end.to raise_error(Volcano::Error::AuthenticationError, 'provider is not linked')
      expect(client.current_session.access_token).to eq('access-token')
      expect(transport.calls.map(&:first)).to eq([:call_oauth_provider_api])
    end

    it 'refreshes an expired session before retrying a provider API call' do
      transport.queue(:call_oauth_provider_api, 401, 'error' => 'not authenticated')
      transport.queue(:auth_refresh, 200, token_payload(access: 'rotated-access'))
      transport.queue(:call_oauth_provider_api, 200, 'login' => 'octocat')

      result = client.auth.call_oauth_api(provider: 'github', endpoint: '/user')

      expect(result).to eq('login' => 'octocat')
      expect(client.current_session.access_token).to eq('rotated-access')
    end

    it 'clears a refreshed session after another auth-level provider rejection' do
      transport.queue(:call_oauth_provider_api, 401, 'error' => 'not authenticated')
      transport.queue(:auth_refresh, 200, token_payload(access: 'rotated-access'))
      transport.queue(:call_oauth_provider_api, 401, 'error' => 'session revoked')

      expect do
        client.auth.call_oauth_api(provider: 'github', endpoint: '/user')
      end.to raise_error(Volcano::Error::AuthenticationError, 'session revoked')
      expect(client.current_session).to be_nil
    end

    it 'preserves refreshed auth for a provider-not-linked retry response' do
      transport.queue(:call_oauth_provider_api, 401, 'error' => 'not authenticated')
      transport.queue(:auth_refresh, 200, token_payload(access: 'rotated-access'))
      transport.queue(
        :call_oauth_provider_api, 401,
        'error' => 'provider unavailable', 'code' => 'provider_not_linked'
      )

      expect do
        client.auth.call_oauth_api(provider: 'github', endpoint: '/user')
      end.to raise_error(Volcano::Error::AuthenticationError, 'provider unavailable')
      expect(client.current_session.access_token).to eq('rotated-access')
    end

    it 'lists and deletes current-user device sessions' do
      session = {
        'id' => 'session-id', 'user_id' => 'user-id', 'provider' => 'password',
        'expires_at' => Time.utc(2026, 8, 29, 12), 'is_active' => true, 'is_current' => true
      }
      transport.queue(:auth_get_my_sessions, 200, 'sessions' => [session], 'total' => 1, 'page' => 1, 'limit' => 20)
      transport.queue(:auth_get_my_sessions, 200, 'sessions' => [], 'total' => 1, 'page' => 2, 'limit' => 20)
      transport.queue(:auth_delete_my_session, 204)
      transport.queue(:auth_delete_all_my_sessions, 204)

      page = client.auth.get_sessions
      client.auth.get_sessions(page: 2)
      results = [
        page.sessions.first.id, page.total,
        client.auth.delete_all_other_sessions,
        client.auth.delete_session(session_id: 'session-id'),
        client.current_session
      ]
      expect(results).to eq(['session-id', 1, nil, nil, nil])
    end

    it 'exposes session filters and cursor navigation' do
      payload = {
        'data' => [current_auth_session], 'total' => 3, 'limit' => 1,
        'has_more' => true, 'next_cursor' => 'next', 'prev_cursor' => 'previous'
      }
      transport.queue(:auth_get_my_sessions, 200, payload)

      page = client.auth.get_sessions(
        sort: 'created_at', status: 'active', cursor: 'cursor', offset: 1, limit: 1
      )

      expect(page.sessions.map(&:id)).to eq(['session-id'])
      expect([page.has_more, page.next_cursor, page.prev_cursor]).to eq([true, 'next', 'previous'])
      expect(transport.calls.last.last).to include(
        sort: 'created_at', status: 'active', cursor: 'cursor', offset: 1, limit: 1
      )
    end

    it 'forgets cached device identity when a legacy session is replaced' do
      session = {
        'id' => 'old-session', 'user_id' => 'user-id', 'provider' => 'password',
        'expires_at' => Time.utc(2026, 8, 29, 12), 'is_active' => true, 'is_current' => true
      }
      transport.queue(:auth_get_my_sessions, 200, 'sessions' => [session])
      transport.queue(:auth_delete_my_session, 204)
      replacement = Volcano::Session.new(access_token: 'replacement-access')

      client.auth.get_sessions
      client.store_session(replacement)
      client.auth.delete_session(session_id: 'old-session')

      expect(client.current_session).to be(replacement)
    end

    it 'deletes the current session after an automatic token refresh' do
      session = {
        'id' => 'session-id', 'user_id' => 'user-id', 'provider' => 'password',
        'expires_at' => Time.utc(2026, 8, 29, 12), 'is_active' => true, 'is_current' => true
      }
      transport.queue(:auth_get_my_sessions, 200, 'sessions' => [session])
      transport.queue(:auth_delete_my_session, 401, 'error' => 'expired')
      transport.queue(:auth_refresh, 200, token_payload(access: 'rotated-access'))
      transport.queue(:auth_delete_my_session, 204)

      client.auth.get_sessions
      client.auth.delete_session(session_id: 'session-id')

      expect(client.current_session).to be_nil
    end

    it 'preserves current-session identity across explicit token refresh' do
      transport.queue(:auth_get_my_sessions, 200, 'sessions' => [current_auth_session])
      transport.queue(:auth_refresh, 200, token_payload(access: 'rotated-access'))
      transport.queue(:auth_delete_my_session, 204)

      client.auth.get_sessions
      client.auth.refresh_session
      client.auth.delete_session(session_id: 'session-id')

      expect(client.current_session).to be_nil
    end

    it 'serializes current-session deletion with replacement sign-in' do
      response = AuthSpecResponse.new(status: 204, body: nil, headers: {}, data: nil)
      serial = BlockingAuthTransport.new(:auth_delete_my_session, response)
      serial.queue(:auth_get_my_sessions, 200, 'sessions' => [current_auth_session])
      serial.queue(:auth_signin, 200, token_payload(access: 'replacement-access'))
      session_client = authenticated_client(serial)
      session_client.auth.get_sessions
      deletion = Thread.new { session_client.auth.delete_session(session_id: 'session-id') }
      serial.entered.pop
      sign_in = Thread.new { session_client.auth.sign_in(email: 'next@example.com', password: 'password') }
      Timeout.timeout(1) { Thread.pass until sign_in.status == 'sleep' }
      serial.release

      expect(
        [deletion.value, sign_in.value.access_token, session_client.current_session.access_token]
      ).to eq([nil, 'replacement-access', 'replacement-access'])
    end

    it 'rejects unsupported providers before transport invocation' do
      expect do
        client.auth.get_oauth_authorization_url(provider: 'unknown', redirect_url: 'https://app.test')
      end.to raise_error(Volcano::Error::ValidationError)
      expect(transport.calls).to be_empty
    end
  end
end
