# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'time'

RSpec.describe Volcano::Client do
  CallbackAbort = Exception unless const_defined?(:CallbackAbort)
  Response = Data.define(:status, :body, :headers, :data) unless const_defined?(:Response)

  def access_token_with_session_id(session_id)
    payload = [JSON.generate(session_id: session_id)].pack('m0').tr('+/', '-_').delete('=')
    "header.#{payload}.signature"
  end

  def anon_key_with_project_id(project_id)
    claims = project_id ? { project_id: project_id } : {}
    payload = [JSON.generate(claims)].pack('m0').tr('+/', '-_').delete('=')
    "header.#{payload}.signature"
  end

  module FakeUserTransport
    attr_accessor :on_get_user, :on_update_user, :update_user_response, :user_response

    def auth_get_user(**arguments)
      @calls << [:auth_get_user, arguments]
      @user_response.tap { @on_get_user&.call }
    end

    def auth_update_user(**arguments)
      @calls << [:auth_update_user, arguments]
      @update_user_response.tap { @on_update_user&.call }
    end
  end

  module FakePasswordRecoveryTransport
    attr_accessor :forgot_password_response, :reset_password_response

    def initialize_password_recovery_response
      @forgot_password_response = Response.new(
        status: 200,
        body: { 'message' => 'If the email exists, a password reset link has been sent.' },
        headers: {},
        data: nil
      )
      @reset_password_response = Response.new(
        status: 200,
        body: { 'message' => 'Password reset successful. Please sign in again.' },
        headers: {},
        data: nil
      )
    end

    def auth_forgot_password(**arguments)
      @calls << [:auth_forgot_password, arguments]
      @forgot_password_response
    end

    def auth_reset_password(**arguments)
      @calls << [:auth_reset_password, arguments]
      @reset_password_response
    end
  end

  module FakeEmailConfirmationTransport
    attr_accessor :confirm_email_response, :resend_confirmation_response

    def initialize_email_confirmation_response
      @confirm_email_response = Response.new(
        status: 200, body: { 'message' => 'Email confirmed successfully' }, headers: {}, data: nil
      )
      @resend_confirmation_response = Response.new(
        status: 200, body: { 'message' => 'If eligible, a confirmation email has been sent.' },
        headers: {}, data: nil
      )
    end

    def auth_confirm_email(**arguments)
      @calls << [:auth_confirm_email, arguments]
      @confirm_email_response
    end

    def auth_resend_confirmation(**arguments)
      @calls << [:auth_resend_confirmation, arguments]
      @resend_confirmation_response
    end
  end

  module FakeCallLog
    def calls_for(name)
      calls.select { |call| call.first == name }
    end
  end

  module FakeEmailChangeTransport
    attr_accessor :cancel_email_change_response, :email_change_response,
                  :confirm_email_change_response, :on_cancel_email_change,
                  :on_confirm_email_change, :on_email_change

    def initialize_email_change_response
      @email_change_response = Response.new(
        status: 200,
        body: { 'message' => 'Confirmation email sent', 'new_email' => 'new@example.com' },
        headers: {}, data: nil
      )
      @cancel_email_change_response = Response.new(status: 200, body: {}, headers: {}, data: nil)
      @confirm_email_change_response = Response.new(
        status: 200,
        body: {
          'user' => { 'id' => 'user-123', 'email' => 'new@example.com', 'status' => 'active' }
        },
        headers: {}, data: nil
      )
    end

    def auth_request_email_change(**arguments)
      @calls << [:auth_request_email_change, arguments]
      @on_email_change&.call
      @email_change_response
    end

    def auth_cancel_email_change(**arguments)
      @calls << [:auth_cancel_email_change, arguments]
      @on_cancel_email_change&.call
      @cancel_email_change_response
    end

    def auth_confirm_email_change(**arguments)
      @calls << [:auth_confirm_email_change, arguments]
      @on_confirm_email_change&.call
      @confirm_email_change_response
    end
  end

  module FakeSessionTransport
    attr_accessor :delete_session_response, :list_sessions_response, :on_delete_other_sessions,
                  :on_delete_session, :on_list_sessions

    def auth_get_my_sessions(**arguments)
      @calls << [:auth_get_my_sessions, arguments]
      @on_list_sessions&.call
      @list_sessions_response || Response.new(
        status: 200,
        body: {
          'sessions' => [
            {
              'id' => '00000000-0000-4000-8000-000000000099',
              'user_id' => '00000000-0000-4000-8000-000000000010',
              'provider' => 'email',
              'user_agent' => 'Volcano Test',
              'ip_address' => '192.0.2.10',
              'last_ip_address' => '192.0.2.11',
              'expires_at' => Time.iso8601('2026-09-02T12:00:00Z'),
              'last_activity_at' => Time.iso8601('2026-09-01T12:00:00Z'),
              'session_started_at' => Time.iso8601('2026-08-31T12:00:00Z'),
              'is_active' => true,
              'is_current' => true,
              'created_at' => Time.iso8601('2026-08-31T12:00:00Z'),
              'updated_at' => Time.iso8601('2026-09-01T12:00:00Z')
            }
          ],
          'total' => 21,
          'page' => 2,
          'limit' => 10,
          'total_pages' => 3
        },
        headers: {},
        data: nil
      )
    end

    def auth_delete_all_my_sessions(**arguments)
      @calls << [:auth_delete_all_my_sessions, arguments]
      @on_delete_other_sessions&.call
      Response.new(status: 204, body: nil, headers: {}, data: nil)
    end

    def auth_delete_my_session(**arguments)
      @calls << [:auth_delete_my_session, arguments]
      @on_delete_session&.call
      @delete_session_response || Response.new(status: 204, body: nil, headers: {}, data: nil)
    end
  end

  FakeEmailChangeTransport.include(FakeSessionTransport)

  module FakeOAuthTransport
    attr_accessor :link_oauth_provider_response, :list_oauth_providers_response,
                  :call_oauth_api_response,
                  :on_link_oauth_provider, :on_list_oauth_providers,
                  :on_call_oauth_api,
                  :oauth_provider_token_status_response,
                  :on_oauth_exchange, :on_oauth_provider_token_status,
                  :on_refresh_oauth_provider_token,
                  :on_unlink_oauth_provider, :refresh_oauth_provider_token_response

    def auth_oauth_authorization_url(**arguments)
      @calls << [:auth_oauth_authorization_url, arguments]
      'https://api.test.volcano.dev/auth/oauth/github/authorize?anon_key=anon-key'
    end

    def auth_oauth_exchange(**arguments)
      @calls << [:auth_oauth_exchange, arguments]
      @on_oauth_exchange&.call
      Response.new(
        status: 200,
        body: {
          'access_token' => 'oauth-access', 'refresh_token' => 'oauth-refresh',
          'user' => { 'id' => 'oauth-user' }
        },
        headers: {}, data: nil
      )
    end

    def auth_list_oauth_providers(**arguments)
      @calls << [:auth_list_oauth_providers, arguments]
      @on_list_oauth_providers&.call
      @list_oauth_providers_response || Response.new(
        status: 200,
        body: {
          'providers' => [
            {
              'provider' => 'google',
              'linked_at' => Time.iso8601('2026-08-30T12:00:00Z'),
              'updated_at' => Time.iso8601('2026-09-01T12:00:00Z')
            }
          ]
        },
        headers: {}, data: nil
      )
    end

    def auth_link_oauth_provider(**arguments)
      @calls << [:auth_link_oauth_provider, arguments]
      @on_link_oauth_provider&.call
      @link_oauth_provider_response || Response.new(
        status: 200,
        body: { 'authorization_url' => 'https://accounts.example/link' },
        headers: {}, data: nil
      )
    end

    def auth_unlink_oauth_provider(**arguments)
      @calls << [:auth_unlink_oauth_provider, arguments]
      @on_unlink_oauth_provider&.call
      Response.new(status: 204, body: nil, headers: {}, data: nil)
    end

    def auth_get_oauth_provider_token(**arguments)
      @calls << [:auth_get_oauth_provider_token, arguments]
      @on_oauth_provider_token_status&.call
      @oauth_provider_token_status_response || Response.new(
        status: 200,
        body: {
          'message' => 'Provider token is valid',
          'provider' => 'google',
          'expires_in' => 3600
        },
        headers: {}, data: nil
      )
    end

    def auth_refresh_oauth_provider_token(**arguments)
      @calls << [:auth_refresh_oauth_provider_token, arguments]
      @on_refresh_oauth_provider_token&.call
      @refresh_oauth_provider_token_response || Response.new(
        status: 200,
        body: {
          'message' => 'Provider token refreshed successfully',
          'provider' => 'google',
          'expires_in' => 3600
        },
        headers: {}, data: nil
      )
    end

    def auth_call_oauth_api(**arguments)
      @calls << [:auth_call_oauth_api, arguments]
      @on_call_oauth_api&.call
      @call_oauth_api_response || Response.new(
        status: 200,
        body: {
          'provider' => 'github',
          'endpoint' => '/user/repos',
          'status_code' => 200,
          'data' => [{ 'name' => 'volcano' }]
        },
        headers: {}, data: nil
      )
    end
  end

  FakeEmailChangeTransport.include(FakeOAuthTransport)

  module FakeAnonymousTransport
    attr_accessor :anonymous_conversion_response, :anonymous_signin_response,
                  :on_anonymous_conversion, :on_anonymous_signin

    def initialize_anonymous_signin_response
      @anonymous_signin_response = Response.new(
        status: 201,
        body: {
          'access_token' => 'anonymous-access',
          'refresh_token' => 'anonymous-refresh',
          'user' => { 'id' => 'anonymous-user' }
        },
        headers: {},
        data: nil
      )
    end

    def initialize_auth_responses
      initialize_password_recovery_response
      initialize_email_confirmation_response
      initialize_anonymous_signin_response
      initialize_email_change_response
      @anonymous_conversion_response = Response.new(
        status: 200,
        body: {
          'user' => {
            'id' => 'anonymous-user', 'email' => 'converted@example.com',
            'status' => 'active', 'email_confirmed' => false
          }
        },
        headers: {}, data: nil
      )
    end

    def auth_signup_anonymous(**arguments)
      @calls << [:auth_signup_anonymous, arguments]
      @on_anonymous_signin&.call
      @anonymous_signin_response
    end

    def auth_convert_anonymous(**arguments)
      @calls << [:auth_convert_anonymous, arguments]
      @on_anonymous_conversion&.call
      @anonymous_conversion_response
    end
  end

  # Implements the database operations used by the facade test transport.
  module FakeDatabaseTransport
    def query_database_select(**arguments)
      @calls << [:query_database_select, arguments]
      Response.new(status: 200, body: { 'data' => [{ 'slug' => 'a' }] }, headers: {}, data: nil)
    end

    def query_database_insert(**arguments)
      @calls << [:query_database_insert, arguments]
      values = arguments.fetch(:body).fetch('values')
      Response.new(status: 200, body: { 'data' => [values] }, headers: {}, data: nil)
    end

    def query_database_update(**arguments)
      @calls << [:query_database_update, arguments]
      values = arguments.fetch(:body).fetch('values')
      Response.new(status: 200, body: { 'data' => [values] }, headers: {}, data: nil)
    end

    def query_database_delete(**arguments)
      @calls << [:query_database_delete, arguments]
      Response.new(status: 200, body: { 'data' => [{ 'id' => 'item-1' }] }, headers: {}, data: nil)
    end
  end

  # Implements the storage operations used by the facade test transport.
  module FakeStorageTransport
    def upload_storage_object(**arguments)
      @calls << [:upload_storage_object, arguments]
      Response.new(status: 201, body: { 'name' => 'a.txt', 'size' => 5 }, headers: {}, data: nil)
    end

    def download_storage_object(**arguments)
      @calls << [:download_storage_object, arguments]
      status = arguments[:byte_range] ? 206 : 200
      Response.new(status: status, body: nil, headers: {}, data: "hello\x00".b)
    end

    def list_storage_objects(**arguments)
      @calls << [:list_storage_objects, arguments]
      Response.new(status: 200, body: storage_page_body, headers: {}, data: nil)
    end

    def delete_storage_object(**arguments)
      @calls << [:delete_storage_object, arguments]
      Response.new(status: 200, body: nil, headers: {}, data: nil)
    end

    def move_storage_object(**arguments)
      @calls << [:move_storage_object, arguments]
      Response.new(
        status: 200,
        body: {
          'id' => '00000000-0000-4000-8000-000000000020',
          'bucket_id' => '00000000-0000-4000-8000-000000000030',
          'name' => arguments.fetch(:to_path),
          'size' => 5,
          'mime_type' => 'text/plain',
          'is_public' => false
        },
        headers: {},
        data: nil
      )
    end

    def copy_storage_object(**arguments)
      @calls << [:copy_storage_object, arguments]
      Response.new(
        status: 201,
        body: {
          'id' => '00000000-0000-4000-8000-000000000021',
          'bucket_id' => '00000000-0000-4000-8000-000000000030',
          'name' => arguments.fetch(:to_path),
          'size' => 5,
          'mime_type' => 'text/plain',
          'is_public' => false
        },
        headers: {},
        data: nil
      )
    end

    def update_storage_object_visibility(**arguments)
      @calls << [:update_storage_object_visibility, arguments]
      Response.new(
        status: 200,
        body: {
          'id' => '00000000-0000-4000-8000-000000000020',
          'bucket_id' => '00000000-0000-4000-8000-000000000030',
          'name' => arguments.fetch(:path),
          'size' => 5,
          'mime_type' => 'image/png',
          'is_public' => arguments.fetch(:is_public),
          'public_url' => if arguments.fetch(:is_public)
                            'https://api.test.volcano.dev/public/project/assets/avatars/a.png'
                          end
        },
        headers: {},
        data: nil
      )
    end

    private

    def storage_page_body
      {
        'objects' => [
          {
            'id' => '00000000-0000-4000-8000-000000000020',
            'bucket_id' => '00000000-0000-4000-8000-000000000030',
            'name' => 'avatars/a.png',
            'size' => 5,
            'mime_type' => 'image/png',
            'is_public' => false,
            'owner_id' => '00000000-0000-4000-8000-000000000010',
            'etag' => 'etag-1',
            'metadata' => { 'width' => 32, 'labels' => ['profile'] },
            'created_at' => '2026-08-26T12:00:00Z',
            'updated_at' => '2026-08-26T12:01:00Z'
          }
        ],
        'next_cursor' => 'cursor-2'
      }
    end
  end

  class FakeContractTransport
    include FakeDatabaseTransport
    include FakeStorageTransport

    include FakeCallLog
    include FakeEmailChangeTransport
    include FakeAnonymousTransport
    include FakeEmailConfirmationTransport
    include FakePasswordRecoveryTransport
    include FakeUserTransport

    attr_reader :calls
    attr_accessor :access_token, :logout_response, :on_logout, :on_refresh, :refresh_response,
                  :signup_response

    def initialize
      @access_token = 'access-token'
      @signup_response = Response.new(
        status: 201,
        body: {
          'confirmation_required' => true,
          'message' => 'Check your email to confirm your account'
        },
        headers: {},
        data: nil
      )
      initialize_auth_responses
      @user_response = Response.new(
        status: 200,
        body: {
          'user' => {
            'id' => 'user-123',
            'email' => 'user@example.com',
            'status' => 'active',
            'email_confirmed' => true,
            'user_metadata' => { 'display_name' => 'Ada', 'roles' => ['admin'] }
          }
        },
        headers: {},
        data: nil
      )
      @update_user_response = @user_response
      @refresh_response = Response.new(
        status: 200,
        body: {
          'access_token' => 'access-2',
          'refresh_token' => 'refresh-2',
          'user' => { 'id' => 'user-123' }
        },
        headers: {},
        data: nil
      )
      @logout_response = Response.new(status: 204, body: nil, headers: {}, data: nil)
      @calls = []
    end

    def auth_logout(**arguments)
      @calls << [:auth_logout, arguments]
      @logout_response.tap { @on_logout&.call }
    end

    def auth_refresh(**arguments)
      @calls << [:auth_refresh, arguments]
      @on_refresh&.call
      @refresh_response
    end

    def auth_signin(**arguments)
      @calls << [:auth_signin, arguments]
      Response.new(
        status: 200,
        body: {
          'access_token' => access_token,
          'refresh_token' => 'refresh-token',
          'user' => { 'id' => 'user-123' }
        },
        headers: {},
        data: nil
      )
    end

    def auth_signup(**arguments)
      @calls << [:auth_signup, arguments]
      @signup_response
    end

    def acquire_project_lock(**arguments)
      @calls << [:acquire_project_lock, arguments]
      Response.new(
        status: 201,
        body: { 'expires_at' => Time.iso8601('2026-08-26T12:00:30Z'), 'fencing_token' => 7 },
        headers: {},
        data: nil
      )
    end

    def release_project_lock(**arguments)
      @calls << [:release_project_lock, arguments]
      Response.new(status: 204, body: nil, headers: {}, data: nil)
    end
  end

  let(:transport) { FakeContractTransport.new }
  let(:client) do
    described_class.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: 'anon-key',
      service_key: 'service-key',
      _transport: transport
    )
  end

  let(:results) do
    session = client.auth.sign_in(email: 'user@example.com', password: 'secret')
    rows = client.database('main').from('items').select('*').eq('slug', 'a').execute
    uploaded = client.storage.from('assets').upload('a.txt', StringIO.new("hello\x00".b))
    downloaded = client.storage.from('assets').download('a.txt', range: 'bytes=0-4')
    page = client.storage.from('assets').list('avatars', limit: 25, cursor: 'cursor-1')
    removed = client.storage.from('assets').remove(['archive/a.txt', 'archive/b.txt'])
    lease = client.locks.acquire('build', ttl: 30)
    released = client.locks.release('build', lease)
    {
      session: session,
      rows: rows,
      uploaded: uploaded,
      downloaded: downloaded,
      page: page,
      removed: removed,
      lease: lease,
      released: released
    }
  end

  def supplied_session
    Volcano::Session.new(
      access_token: +'adopted-access', refresh_token: +'adopted-refresh', user_id: +'adopted-user'
    )
  end

  it 'returns nil without a current session or transport call' do
    expect(client.auth.current_session).to be_nil
    expect(transport.calls).to be_empty
  end

  it 'returns the established immutable session without a transport call' do
    transport.access_token = +'access-token'
    established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
    calls_after_sign_in = transport.calls.dup

    current = client.auth.current_session

    expect(current).to be(established)
    expect { current.access_token = 'changed' }.to raise_error(NoMethodError)
    expect { current.access_token.replace('changed') }.to raise_error(FrozenError)
    expect(transport.calls).to eq(calls_after_sign_in)
  end

  it 'reports local auth-state transitions to subscribers', :aggregate_failures do
    events = []
    subscription = client.auth.on_auth_state_change do |event, session|
      events << [event, session]
    end

    signed_in = client.auth.sign_in(email: 'user@example.com', password: 'secret')
    refreshed = client.auth.refresh_session
    client.auth.sign_out

    expect(subscription).to be_a(Volcano::AuthSubscription)
    expect(events).to eq(
      [
        [:initial_session, nil],
        [:signed_in, signed_in],
        [:token_refreshed, refreshed],
        [:signed_out, nil]
      ]
    )
  end

  it 'unsubscribes from auth-state changes idempotently' do
    events = []
    subscription = client.auth.on_auth_state_change do |event, session|
      events << [event, session]
    end

    subscription.unsubscribe
    subscription.unsubscribe
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(events).to eq([[:initial_session, nil]])
  end

  it 'requires a callback block for auth-state changes' do
    expect { client.auth.on_auth_state_change }.to raise_error(
      ArgumentError,
      'callback block required'
    )
  end

  it 'isolates subscriber failures from auth operations and other subscribers' do
    allow(Warning).to receive(:warn)
    received = []
    client.auth.on_auth_state_change { raise 'subscriber failed' }
    client.auth.on_auth_state_change do |event, session|
      received << [event, session]
    end

    signed_in = client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(received).to eq([[:initial_session, nil], [:signed_in, signed_in]])
  end

  it 'preserves notification order during reentrant auth changes' do
    received = []
    client.auth.on_auth_state_change do |event, _session|
      client.auth.sign_out if event == :signed_in
    end
    client.auth.on_auth_state_change do |event, session|
      received << [event, session]
    end
    received.clear

    signed_in = client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(received).to eq([[:signed_in, signed_in], [:signed_out, nil]])
  end

  it 'skips queued reentrant changes after unsubscription' do
    received = []
    client.auth.on_auth_state_change do |event, _session|
      client.auth.sign_out if event == :signed_in
    end
    subscription = nil
    subscription = client.auth.on_auth_state_change do |event, _session|
      received << event
      subscription.unsubscribe if event == :signed_in
    end
    received.clear

    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(received).to eq([:signed_in])
  end

  it 'recovers notification dispatch after an interrupt' do
    received = []
    interrupting = client.auth.on_auth_state_change do |event, _session|
      raise Interrupt if event == :signed_in
    end
    client.auth.on_auth_state_change do |event, _session|
      received << event
    end
    received.clear

    expect do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
    end.to raise_error(Interrupt)

    interrupting.unsubscribe
    client.auth.sign_out

    expect(received).to eq(%i[signed_in signed_out])
  end

  it 'rolls back a subscription when initial delivery is interrupted' do
    received = []
    observed = []
    expect do
      client.auth.on_auth_state_change do |event, _session|
        received << event
        raise CallbackAbort
      end
    end.to raise_error(CallbackAbort)

    client.auth.on_auth_state_change { |event, _session| observed << event }
    expect { client.auth.sign_in(email: 'user@example.com', password: 'secret') }.not_to raise_error
    expect(received).to eq([:initial_session])
    expect(observed).to eq(%i[initial_session signed_in])
  end

  it 'preserves concurrent notifications when a callback is interrupted' do
    entered = Queue.new
    release = Queue.new
    received = []
    client.auth.on_auth_state_change do |event, _session|
      next unless event == :signed_in

      entered << true
      release.pop
      raise CallbackAbort
    end
    client.auth.on_auth_state_change { |event, _session| received << event }
    received.clear
    sign_out = Thread.new { entered.pop.then { client.auth.sign_out }.then { release << true } }

    expect { client.auth.sign_in(email: 'user@example.com', password: 'secret') }.to raise_error(CallbackAbort)
    sign_out.value
    expect(received).to eq(%i[signed_in signed_out])
  end

  describe '#sign_up' do
    it 'returns an owned acknowledgement without changing the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.sign_up(
        email: 'new@example.com',
        password: 'secret',
        metadata: { display_name: 'New User' }
      )

      expect(result).to eq(
        Volcano::SignUpResult.new(
          confirmation_required: true,
          message: 'Check your email to confirm your account'
        )
      )
      expect(result.message).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_signup).last.fetch(1)).to eq(
        authorization: 'anon-key',
        email: 'new@example.com',
        password: 'secret',
        metadata: { display_name: 'New User' }
      )
    end

    it 'uses empty metadata without creating a session' do
      client.auth.sign_up(email: 'new@example.com', password: 'secret')

      expect(client.auth.current_session).to be_nil
      expect(transport.calls_for(:auth_signup).last.fetch(1).fetch(:metadata)).to eq({})
    end

    it 'raises a typed error without changing the session' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.signup_response = Response.new(
        status: 403, body: { 'error' => 'Signups are disabled' }, headers: {}, data: nil
      )

      expect { client.auth.sign_up(email: 'new@example.com', password: 'secret') }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Signups are disabled'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'rejects a malformed acknowledgement' do
      transport.signup_response = Response.new(
        status: 201,
        body: { 'confirmation_required' => 'yes', 'message' => 'Created' },
        headers: {},
        data: nil
      )

      expect { client.auth.sign_up(email: 'new@example.com', password: 'secret') }.to raise_error(
        TypeError,
        'Expected a complete sign-up acknowledgement'
      )
    end
  end

  describe '#sign_in_anonymously' do
    it 'stores the returned session and sends metadata', :aggregate_failures do
      session = client.auth.sign_in_anonymously(metadata: { device: 'mobile' })

      expect(session).to eq(
        Volcano::Session.new(
          access_token: 'anonymous-access',
          refresh_token: 'anonymous-refresh',
          user_id: 'anonymous-user'
        )
      )
      expect(client.auth.current_session).to be(session)
      expect(transport.calls_for(:auth_signup_anonymous).last.fetch(1)).to eq(
        authorization: 'anon-key', metadata: { device: 'mobile' }
      )
    end

    it 'does not replace a newer session' do
      replacement = Volcano::Session.new(
        access_token: 'replacement-access',
        refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_anonymous_signin = -> { client.auth.current_session = replacement }

      expect { client.auth.sign_in_anonymously }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end

    it 'preserves the current session when anonymous sign-ins are disabled' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.anonymous_signin_response = Response.new(
        status: 403, body: { 'error' => 'Anonymous sign-ins are disabled' }, headers: {}, data: nil
      )

      expect { client.auth.sign_in_anonymously }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Anonymous sign-ins are disabled'
      )
      expect(client.auth.current_session).to be(established)
    end
  end

  describe '#convert_anonymous' do
    it 'returns the converted user without replacing the session', :aggregate_failures do
      established = client.auth.sign_in_anonymously

      user = client.auth.convert_anonymous(
        email: 'converted@example.com',
        password: 'secret',
        metadata: { display_name: 'Ada' }
      )

      expect(user).to have_attributes(
        id: 'anonymous-user', email: 'converted@example.com', email_confirmed: false
      )
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_convert_anonymous).last.fetch(1)).to eq(
        authorization: 'anonymous-access',
        email: 'converted@example.com',
        password: 'secret',
        metadata: { display_name: 'Ada' }
      )
    end

    it 'requires a session' do
      expect do
        client.auth.convert_anonymous(email: 'converted@example.com', password: 'secret')
      end.to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_convert_anonymous)).to be_empty
    end

    it 'does not return a stale response' do
      client.auth.sign_in_anonymously
      replacement = Volcano::Session.new(
        access_token: 'replacement-access',
        refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_anonymous_conversion = -> { client.auth.current_session = replacement }

      expect do
        client.auth.convert_anonymous(email: 'converted@example.com', password: 'secret')
      end.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#request_email_change' do
    it 'returns an acknowledgement without replacing the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.request_email_change(new_email: 'new@example.com')

      expect(result).to eq(
        Volcano::EmailChangeResult.new(
          message: 'Confirmation email sent', new_email: 'new@example.com'
        )
      )
      expect(client.auth.current_session).to be(established)
      expect(result.message).to be_frozen
      expect(result.new_email).to be_frozen
      expect(transport.calls_for(:auth_request_email_change).last.fetch(1)).to eq(
        authorization: 'access-token', new_email: 'new@example.com'
      )
    end

    it 'accepts an acknowledgement without optional fields' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.email_change_response = Response.new(status: 200, body: {}, headers: {}, data: nil)

      result = client.auth.request_email_change(new_email: 'new@example.com')

      expect(result).to eq(Volcano::EmailChangeResult.new(message: nil, new_email: nil))
    end

    it 'rejects a non-object acknowledgement' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.email_change_response = Response.new(status: 200, body: [], headers: {}, data: nil)

      expect do
        client.auth.request_email_change(new_email: 'new@example.com')
      end.to raise_error(TypeError, 'Expected a valid email-change acknowledgement')
    end

    it 'requires a session' do
      expect do
        client.auth.request_email_change(new_email: 'new@example.com')
      end.to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_request_email_change)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access',
        refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_email_change = -> { client.auth.current_session = replacement }

      expect do
        client.auth.request_email_change(new_email: 'new@example.com')
      end.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#cancel_email_change' do
    it 'preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.cancel_email_change

      expect(result).to be_nil
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_cancel_email_change).last.fetch(1)).to eq(
        authorization: 'access-token'
      )
    end

    it 'requires a session' do
      expect { client.auth.cancel_email_change }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_cancel_email_change)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access',
        refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_cancel_email_change = -> { client.auth.current_session = replacement }

      expect { client.auth.cancel_email_change }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#confirm_email_change' do
    it 'returns the updated user without replacing the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      user = client.auth.confirm_email_change(token: 'change-token')

      expect(user).to have_attributes(email: 'new@example.com', status: 'active')
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_confirm_email_change).last.fetch(1)).to eq(
        authorization: 'access-token', token: 'change-token'
      )
    end

    it 'requires a session' do
      expect { client.auth.confirm_email_change(token: 'change-token') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_confirm_email_change)).to be_empty
    end

    it 'rejects a missing user' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.confirm_email_change_response = Response.new(
        status: 200, body: {}, headers: {}, data: nil
      )

      expect { client.auth.confirm_email_change(token: 'change-token') }
        .to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile')
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access',
        refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_confirm_email_change = -> { client.auth.current_session = replacement }

      expect { client.auth.confirm_email_change(token: 'change-token') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#list_sessions' do
    it 'returns an immutable offset page and preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.list_sessions(page: 2, limit: 10)

      expect(result).to be_a(Volcano::SessionPage)
        .and have_attributes(total: 21, page: 2, limit: 10, total_pages: 3)
      expect(result.sessions).to contain_exactly(
        Volcano::AuthSession.new(
          id: '00000000-0000-4000-8000-000000000099',
          user_id: '00000000-0000-4000-8000-000000000010',
          provider: 'email',
          user_agent: 'Volcano Test',
          ip_address: '192.0.2.10',
          last_ip_address: '192.0.2.11',
          expires_at: Time.iso8601('2026-09-02T12:00:00Z'),
          last_activity_at: Time.iso8601('2026-09-01T12:00:00Z'),
          session_started_at: Time.iso8601('2026-08-31T12:00:00Z'),
          is_active: true,
          is_current: true,
          created_at: Time.iso8601('2026-08-31T12:00:00Z'),
          updated_at: Time.iso8601('2026-09-01T12:00:00Z')
        )
      )
      expect(result.sessions).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_get_my_sessions).last.fetch(1)).to eq(
        authorization: 'access-token', page: 2, limit: 10
      )
    end

    it 'requires a session' do
      expect { client.auth.list_sessions }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_get_my_sessions)).to be_empty
    end

    it 'copies a caller-owned sessions array before freezing it' do
      session = Volcano::AuthSession.new(
        id: 'session-id', user_id: 'user-id', provider: 'email',
        expires_at: Time.iso8601('2026-09-02T12:00:00Z'), is_active: true, is_current: true
      )
      sessions = [session]

      result = Volcano::SessionPage.new(
        sessions: sessions, total: 1, page: 1, limit: 20, total_pages: 1
      )

      expect(result.sessions).not_to be(sessions)
      expect(result.sessions).to be_frozen
      expect(sessions).not_to be_frozen
      expect { sessions << session }.not_to raise_error
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_list_sessions = -> { client.auth.current_session = replacement }

      expect { client.auth.list_sessions }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#list_linked_oauth_providers' do
    it 'returns immutable linked-provider values and preserves the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.list_linked_oauth_providers

      expect(result).to contain_exactly(
        Volcano::LinkedOAuthProvider.new(
          provider: 'google',
          linked_at: Time.iso8601('2026-08-30T12:00:00Z'),
          updated_at: Time.iso8601('2026-09-01T12:00:00Z')
        )
      )
      expect(result).to be_frozen
      expect(result.first).to be_frozen
      expect(result.first.provider).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_list_oauth_providers).last.fetch(1)).to eq(
        authorization: 'access-token'
      )
    end

    it 'requires a session' do
      expect { client.auth.list_linked_oauth_providers }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_list_oauth_providers)).to be_empty
    end

    it 'rejects an incomplete provider' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.list_oauth_providers_response = Response.new(
        status: 200, body: { 'providers' => [{ 'provider' => 'google' }] },
        headers: {}, data: nil
      )

      expect { client.auth.list_linked_oauth_providers }
        .to raise_error(TypeError, 'Expected complete linked OAuth providers')
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_list_oauth_providers = -> { client.auth.current_session = replacement }

      expect { client.auth.list_linked_oauth_providers }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#sign_in_with_oauth' do
    it 'returns an authorization URL without creating a session', :aggregate_failures do
      result = client.auth.sign_in_with_oauth(
        'github', redirect_to: 'https://app.example.test/auth/callback', state: 'state-value'
      )

      expect(result).to start_with('https://api.test.volcano.dev/auth/oauth/github/authorize')
      expect(client.auth.current_session).to be_nil
      expect(transport.calls_for(:auth_oauth_authorization_url).last.fetch(1)).to eq(
        anon_key: 'anon-key', provider: 'github',
        redirect_url: 'https://app.example.test/auth/callback', client_state: 'state-value'
      )
    end

    it 'rejects an unknown provider before building a URL' do
      expect do
        client.auth.sign_in_with_oauth(
          'invalid', redirect_to: 'https://app.example.test/auth/callback', state: 'state-value'
        )
      end
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_oauth_authorization_url)).to be_empty
    end

    it 'exchanges a code for the current session after validating state', :aggregate_failures do
      result = client.auth.exchange_oauth_code(
        code: 'oauth-code', redirect_to: 'https://app.example.test/auth/callback',
        state: 'state-value', expected_state: 'state-value'
      )

      expect(result).to eq(
        Volcano::Session.new(
          access_token: 'oauth-access', refresh_token: 'oauth-refresh', user_id: 'oauth-user'
        )
      )
      expect(client.auth.current_session).to be(result)
      expect(transport.calls_for(:auth_oauth_exchange).last.fetch(1)).to eq(
        authorization: 'anon-key', code: 'oauth-code',
        redirect_url: 'https://app.example.test/auth/callback'
      )
    end

    it 'rejects a mismatched callback state before exchange' do
      expect do
        client.auth.exchange_oauth_code(
          code: 'oauth-code', redirect_to: 'https://app.example.test/auth/callback',
          state: 'attacker-state', expected_state: 'expected-state'
        )
      end.to raise_error(ArgumentError, 'OAuth state mismatch')
      expect(transport.calls_for(:auth_oauth_exchange)).to be_empty
    end

    it 'does not replace a session changed during exchange' do
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_oauth_exchange = -> { client.auth.current_session = replacement }

      expect do
        client.auth.exchange_oauth_code(
          code: 'oauth-code', redirect_to: 'https://app.example.test/auth/callback',
          state: 'state-value', expected_state: 'state-value'
        )
      end.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#get_hosted_auth_url' do
    it 'builds the unified hosted-auth URL for every supported action' do
      urls = %w[login signup forgot-password].to_h do |action|
        [action, client.auth.get_hosted_auth_url(
          project_id: 'project/id', state: 'state value', action: action
        )]
      end

      expect(urls).to eq(
        'login' => 'https://api.test.volcano.dev/projects/project%2Fid/auth/hosted?action=login&anon_key=anon-key&state=state+value',
        'signup' => 'https://api.test.volcano.dev/projects/project%2Fid/auth/hosted?action=signup&anon_key=anon-key&state=state+value',
        'forgot-password' => 'https://api.test.volcano.dev/projects/project%2Fid/auth/hosted?action=forgot-password&anon_key=anon-key&state=state+value'
      )
    end

    it 'defaults to login without creating a session or transport call', :aggregate_failures do
      url = client.auth.get_hosted_auth_url(project_id: 'project-id', state: 'state-value')

      expect(url).to include('/auth/hosted?action=login')
      expect(client.auth.current_session).to be_nil
      expect(transport.calls).to be_empty
    end

    it 'rejects empty parameters' do
      expect do
        client.auth.get_hosted_auth_url(project_id: ' ', state: 'state-value')
      end.to raise_error(ArgumentError, 'Hosted auth parameters must be non-empty strings')
      expect do
        client.auth.get_hosted_auth_url(project_id: 'project-id', state: '')
      end.to raise_error(ArgumentError, 'Hosted auth parameters must be non-empty strings')
    end

    it 'rejects an unsupported action' do
      expect do
        client.auth.get_hosted_auth_url(
          project_id: 'project-id', state: 'state-value', action: 'device'
        )
      end.to raise_error(ArgumentError, 'Unsupported hosted auth action')
    end
  end

  describe '#adopt_hosted_auth_session' do
    let(:returned_session) do
      Volcano::Session.new(
        access_token: 'hosted-access', refresh_token: 'hosted-refresh', user_id: 'hosted-user'
      )
    end

    it 'validates state and stores an owned session copy', :aggregate_failures do
      adopted = client.auth.adopt_hosted_auth_session(
        returned_session, state: 'returned-state', expected_state: 'returned-state'
      )

      expect(adopted).to eq(returned_session)
      expect(adopted).not_to be(returned_session)
      expect(client.auth.current_session).to be(adopted)
    end

    it 'returns the adopted snapshot after a subscriber replaces current state' do
      client.auth.on_auth_state_change do |event, _session|
        client.auth.sign_out if event == :signed_in
      end

      adopted = client.auth.adopt_hosted_auth_session(
        returned_session, state: 'returned-state', expected_state: 'returned-state'
      )

      expect(adopted).to eq(returned_session)
      expect(client.auth.current_session).to be_nil
    end

    it 'preserves the current session when state does not match' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      expect do
        client.auth.adopt_hosted_auth_session(
          returned_session, state: 'attacker-state', expected_state: 'expected-state'
        )
      end.to raise_error(ArgumentError, 'Hosted auth state mismatch')
      expect(client.auth.current_session).to be(established)
    end

    it 'rejects empty returned or expected state' do
      expect do
        client.auth.adopt_hosted_auth_session(
          returned_session, state: ' ', expected_state: 'state-value'
        )
      end.to raise_error(ArgumentError, 'Hosted auth parameters must be non-empty strings')
      expect do
        client.auth.adopt_hosted_auth_session(
          returned_session, state: 'state-value', expected_state: ''
        )
      end.to raise_error(ArgumentError, 'Hosted auth parameters must be non-empty strings')
    end
  end

  describe '#link_oauth_provider' do
    it 'returns the authorization URL and preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.link_oauth_provider('github')

      expect(result).to eq('https://accounts.example/link')
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_link_oauth_provider).last.fetch(1)).to eq(
        authorization: 'access-token', provider: 'github'
      )
    end

    it 'rejects an unknown provider before sending a request' do
      expect { client.auth.link_oauth_provider('invalid') }
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_link_oauth_provider)).to be_empty
    end

    it 'requires a session' do
      expect { client.auth.link_oauth_provider('google') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_link_oauth_provider)).to be_empty
    end

    it 'rejects an incomplete response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.link_oauth_provider_response = Response.new(
        status: 200, body: {}, headers: {}, data: nil
      )

      expect { client.auth.link_oauth_provider('google') }
        .to raise_error(TypeError, 'Expected an OAuth authorization URL')
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_link_oauth_provider = -> { client.auth.current_session = replacement }

      expect { client.auth.link_oauth_provider('google') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#unlink_oauth_provider' do
    it 'preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.unlink_oauth_provider('github')

      expect(result).to be_nil
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_unlink_oauth_provider).last.fetch(1)).to eq(
        authorization: 'access-token', provider: 'github'
      )
    end

    it 'rejects an unknown provider before sending a request' do
      expect { client.auth.unlink_oauth_provider('invalid') }
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_unlink_oauth_provider)).to be_empty
    end

    it 'requires a session' do
      expect { client.auth.unlink_oauth_provider('google') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_unlink_oauth_provider)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_unlink_oauth_provider = -> { client.auth.current_session = replacement }

      expect { client.auth.unlink_oauth_provider('google') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#get_oauth_provider_token' do
    it 'returns immutable token metadata and preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.get_oauth_provider_token('google')

      expect(result).to eq(
        Volcano::OAuthProviderTokenStatus.new(
          message: 'Provider token is valid', provider: 'google', expires_in: 3600
        )
      )
      expect(result).to be_frozen
      expect(result.message).to be_frozen
      expect(result.provider).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_get_oauth_provider_token).last.fetch(1)).to eq(
        authorization: 'access-token', provider: 'google'
      )
    end

    it 'rejects an unknown provider before sending a request' do
      expect { client.auth.get_oauth_provider_token('invalid') }
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_get_oauth_provider_token)).to be_empty
    end

    it 'requires a session' do
      expect { client.auth.get_oauth_provider_token('google') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_get_oauth_provider_token)).to be_empty
    end

    it 'rejects incomplete token metadata' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.oauth_provider_token_status_response = Response.new(
        status: 200, body: { 'provider' => 'google', 'expires_in' => 3600 },
        headers: {}, data: nil
      )

      expect { client.auth.get_oauth_provider_token('google') }
        .to raise_error(TypeError, 'Expected complete OAuth provider token status')
    end

    it 'accepts a future provider name returned by the server' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.oauth_provider_token_status_response = Response.new(
        status: 200,
        body: {
          'message' => 'Provider token is valid',
          'provider' => 'future-provider',
          'expires_in' => 3600
        },
        headers: {}, data: nil
      )

      expect(client.auth.get_oauth_provider_token('google').provider).to eq('future-provider')
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_oauth_provider_token_status = -> { client.auth.current_session = replacement }

      expect { client.auth.get_oauth_provider_token('google') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#refresh_oauth_provider_token' do
    it 'returns immutable token metadata and preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.refresh_oauth_provider_token('google')

      expect(result).to eq(
        Volcano::OAuthProviderTokenStatus.new(
          message: 'Provider token refreshed successfully', provider: 'google', expires_in: 3600
        )
      )
      expect(result).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_refresh_oauth_provider_token).last.fetch(1)).to eq(
        authorization: 'access-token', provider: 'google'
      )
    end

    it 'rejects an unknown provider before sending a request' do
      expect { client.auth.refresh_oauth_provider_token('invalid') }
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_refresh_oauth_provider_token)).to be_empty
    end

    it 'requires a session' do
      expect { client.auth.refresh_oauth_provider_token('google') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_refresh_oauth_provider_token)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_refresh_oauth_provider_token = -> { client.auth.current_session = replacement }

      expect { client.auth.refresh_oauth_provider_token('google') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#call_oauth_api' do
    it 'returns immutable provider data and preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.call_oauth_api(
        'github', endpoint: '/user/repos', method: 'POST', body: { 'visibility' => 'private' }
      )

      expect(result).to eq([{ 'name' => 'volcano' }])
      expect(result).to be_frozen
      expect(result.first).to be_frozen
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_call_oauth_api).last.fetch(1)).to eq(
        authorization: 'access-token', provider: 'github', endpoint: '/user/repos',
        method: 'POST', body: { 'visibility' => 'private' }
      )
    end

    it 'rejects an unknown provider before sending a request' do
      expect { client.auth.call_oauth_api('invalid', endpoint: '/user') }
        .to raise_error(ArgumentError, 'Unsupported OAuth provider')
      expect(transport.calls_for(:auth_call_oauth_api)).to be_empty
    end

    it 'requires a session' do
      expect { client.auth.call_oauth_api('github', endpoint: '/user') }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_call_oauth_api)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_call_oauth_api = -> { client.auth.current_session = replacement }

      expect { client.auth.call_oauth_api('github', endpoint: '/user') }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#delete_all_other_sessions' do
    it 'preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.delete_all_other_sessions

      expect(result).to be_nil
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_delete_all_my_sessions).last.fetch(1)).to eq(
        authorization: 'access-token'
      )
    end

    it 'requires a session' do
      expect { client.auth.delete_all_other_sessions }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_delete_all_my_sessions)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_delete_other_sessions = -> { client.auth.current_session = replacement }

      expect { client.auth.delete_all_other_sessions }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#delete_session' do
    let(:session_id) { '00000000-0000-4000-8000-000000000099' }

    it 'preserves the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.delete_session(session_id)

      expect(result).to be_nil
      expect(client.auth.current_session).to be(established)
      expect(transport.calls_for(:auth_delete_my_session).last.fetch(1)).to eq(
        authorization: 'access-token', session_id: session_id
      )
    end

    it 'requires a session' do
      expect { client.auth.delete_session(session_id) }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.calls_for(:auth_delete_my_session)).to be_empty
    end

    it 'rejects a stale response' do
      client.auth.current_session = Volcano::Session.new(
        access_token: access_token_with_session_id(session_id),
        refresh_token: 'original-refresh',
        user_id: 'original-user'
      )
      replacement = Volcano::Session.new(
        access_token: 'replacement-access', refresh_token: 'replacement-refresh',
        user_id: 'replacement-user'
      )
      transport.on_delete_session = -> { client.auth.current_session = replacement }

      expect { client.auth.delete_session(session_id) }
        .to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end

    it 'clears the deleted current session' do
      upper_session_id = '00000000-0000-4000-8000-0000000000AB'
      client.auth.current_session = Volcano::Session.new(
        access_token: access_token_with_session_id(upper_session_id.downcase),
        refresh_token: 'current-refresh',
        user_id: 'current-user'
      )

      client.auth.delete_session(upper_session_id)

      expect(client.auth.current_session).to be_nil
    end

    it 'clears current state when the deletion response is lost' do
      client.auth.current_session = Volcano::Session.new(
        access_token: access_token_with_session_id(session_id),
        refresh_token: 'current-refresh',
        user_id: 'current-user'
      )
      transport.on_delete_session = -> { raise IOError, 'connection lost' }

      expect { client.auth.delete_session(session_id) }
        .to raise_error(Volcano::Error::TransportError, 'connection lost')
      expect(client.auth.current_session).to be_nil
    end

    it 'preserves current state when the server rejects deletion' do
      current = Volcano::Session.new(
        access_token: access_token_with_session_id(session_id),
        refresh_token: 'current-refresh',
        user_id: 'current-user'
      )
      client.auth.current_session = current
      stored = client.auth.current_session
      transport.delete_session_response = Response.new(
        status: 401, body: { 'error' => 'expired' }, headers: {}, data: nil
      )

      expect { client.auth.delete_session(session_id) }
        .to raise_error(Volcano::Error::AuthenticationError, 'expired')
      expect(client.auth.current_session).to be(stored)
    end
  end

  describe '#reset_password_for_email' do
    it 'requests delivery without changing the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      result = client.auth.reset_password_for_email(email: 'user@example.com')

      expect(result).to be_nil
      expect(transport.calls_for(:auth_forgot_password).last.fetch(1)).to eq(
        authorization: 'anon-key', email: 'user@example.com'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'raises a typed error without changing the session' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.forgot_password_response = Response.new(
        status: 403, body: { 'error' => 'Password reset disabled' }, headers: {}, data: nil
      )

      expect do
        client.auth.reset_password_for_email(email: 'user@example.com')
      end.to raise_error(Volcano::Error::AuthenticationError, 'Password reset disabled')
      expect(client.auth.current_session).to be(established)
    end

    it 'accepts an acknowledgement without the optional message' do
      transport.forgot_password_response = Response.new(
        status: 200, body: {}, headers: {}, data: nil
      )

      expect(client.auth.reset_password_for_email(email: 'user@example.com')).to be_nil
    end
  end

  describe '#reset_password' do
    it 'uses the recovery token without changing an unrelated session', :aggregate_failures do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')

      result = client.auth.reset_password(token: 'recovery-token', new_password: 'new-secret')

      expect(result).to be_nil
      expect(transport.calls_for(:auth_reset_password).last.fetch(1)).to eq(
        authorization: 'anon-key', token: 'recovery-token', new_password: 'new-secret'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'raises a typed error without changing the session' do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')
      transport.reset_password_response = Response.new(
        status: 401, body: nil, headers: {}, data: nil
      )

      expect do
        client.auth.reset_password(token: 'expired-token', new_password: 'new-secret')
      end.to raise_error(Volcano::Error::AuthenticationError)
      expect(client.auth.current_session).to be(established)
    end
  end

  describe '#confirm_email' do
    it 'uses the confirmation token without changing an unrelated session', :aggregate_failures do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')

      result = client.auth.confirm_email(token: 'confirmation-token')

      expect(result).to be_nil
      expect(transport.calls_for(:auth_confirm_email).last.fetch(1)).to eq(
        authorization: 'anon-key', token: 'confirmation-token'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'raises a typed error without changing the session' do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')
      transport.confirm_email_response = Response.new(
        status: 401, body: nil, headers: {}, data: nil
      )

      expect do
        client.auth.confirm_email(token: 'expired-token')
      end.to raise_error(Volcano::Error::AuthenticationError)
      expect(client.auth.current_session).to be(established)
    end
  end

  describe '#resend_confirmation' do
    it 'is enumeration-safe without changing an unrelated session', :aggregate_failures do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')

      result = client.auth.resend_confirmation(email: 'user@example.com')

      expect(result).to be_nil
      expect(transport.calls_for(:auth_resend_confirmation).last.fetch(1)).to eq(
        authorization: 'anon-key', email: 'user@example.com'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'preserves rate-limit metadata without changing the session' do
      established = client.auth.sign_in(email: 'other@example.com', password: 'secret')
      transport.resend_confirmation_response = Response.new(
        status: 429, body: { 'error' => 'Too many requests' },
        headers: { 'Retry-After' => '17' }, data: nil
      )

      expect do
        client.auth.resend_confirmation(email: 'user@example.com')
      end.to raise_error(Volcano::Error::RateLimitedError) { |error| expect(error.retry_after).to eq(17) }
      expect(client.auth.current_session).to be(established)
    end
  end

  describe '#user' do
    it 'returns the server-validated profile through the access token', :aggregate_failures do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')

      user = client.auth.user

      expect(user).to have_attributes(
        id: 'user-123', email: 'user@example.com', status: 'active', email_confirmed: true
      )
      expect(user.user_metadata).to eq('display_name' => 'Ada', 'roles' => ['admin'])
      expect(transport.calls_for(:auth_get_user).last.fetch(1)).to eq(authorization: 'access-token')
    end

    it 'owns and deeply freezes user data', :aggregate_failures do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user')['app_metadata'] = { 'provider' => 'email' }

      user = client.auth.user

      expect(user).to be_frozen
      expect(user.email).to be_frozen
      expect(user.user_metadata).to be_frozen
      expect(user.user_metadata.fetch('roles')).to be_frozen
      expect(user.app_metadata).to be_frozen
      expect { user.user_metadata.fetch('roles') << 'editor' }.to raise_error(FrozenError)
    end

    it 'preserves the optional profile fields' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user').merge!(
        'project_id' => 'project-123',
        'app_metadata' => { 'provider' => 'email' },
        'avatar_url' => 'https://example.com/avatar.png',
        'banned_until' => nil,
        'last_sign_in_at' => '2026-08-31T12:00:00z',
        'created_at' => '2026-08-30T12:00:00Z',
        'updated_at' => '2026-08-31T17:30:00+05:30'
      )

      user = client.auth.user

      expect(user).to have_attributes(
        project_id: 'project-123', app_metadata: { 'provider' => 'email' },
        avatar_url: 'https://example.com/avatar.png', banned_until: nil,
        last_sign_in_at: Time.iso8601('2026-08-31T12:00:00z'),
        created_at: Time.iso8601('2026-08-30T12:00:00Z'),
        updated_at: Time.iso8601('2026-08-31T17:30:00+05:30')
      )
    end

    it 'does not replace the current session' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      client.auth.user

      expect(client.auth.current_session).to be(established)
    end

    it 'accepts a profile without an email address' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user')['email'] = ''

      user = client.auth.user

      expect(user.email).to eq('')
    end

    it 'rejects a missing session before transport' do
      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'No active session'
      )
      expect(transport.calls).to be_empty
    end

    it 'preserves the current session after an authentication failure' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response = Response.new(
        status: 401, body: { 'error' => 'expired' }, headers: {}, data: nil
      )

      expect { client.auth.user }.to raise_error(Volcano::Error::AuthenticationError, 'expired')
      expect(client.auth.current_session).to be(established)
    end

    it 'rejects a malformed successful profile' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response = Response.new(
        status: 200, body: { 'user' => { 'id' => 'user-123', 'email' => nil } }, headers: {}, data: nil
      )

      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Expected a complete user profile'
      )
    end

    it 'rejects profile values that the generated client would coerce' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user').merge!('id' => 123, 'email' => { 'value' => 'x' })

      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Expected a complete user profile'
      )
    end

    it 'rejects invalid status and timestamp values' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user').merge!(
        'status' => 'pending', 'created_at' => 'not-a-timestamp'
      )

      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Expected a complete user profile'
      )
    end

    it 'rejects timestamps without an RFC 3339 offset' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response.body.fetch('user')['created_at'] = '2026-08-31T12:00:00'

      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Expected a complete user profile'
      )
    end

    it 'rejects a malformed successful envelope with a typed error' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.user_response = Response.new(status: 200, body: nil, headers: {}, data: nil)

      expect { client.auth.user }.to raise_error(
        Volcano::Error::AuthenticationError,
        'Expected a complete user profile'
      )
    end

    it 'rejects a profile loaded for a replaced session' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = supplied_session
      transport.on_get_user = -> { client.auth.current_session = replacement }

      expect { client.auth.user }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end

    it 'provides get_user as the cross-SDK alias' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')

      expect(client.auth.get_user).to be_a(Volcano::User)
    end
  end

  describe '#update_user' do
    it 'returns the updated profile without replacing the session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      user = client.auth.update_user(
        password: 'new-secret',
        metadata: { display_name: 'Grace', avatar: nil }
      )

      expect(user).to have_attributes(id: 'user-123', email: 'user@example.com', status: 'active')
      expect(transport.calls_for(:auth_update_user).last.fetch(1)).to eq(
        authorization: 'access-token',
        password: 'new-secret',
        metadata: { display_name: 'Grace', avatar: nil }
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'rejects a missing session before transport' do
      expect { client.auth.update_user(metadata: { display_name: 'Grace' }) }.to raise_error(
        Volcano::Error::AuthenticationError,
        'No active session'
      )
      expect(transport.calls).to be_empty
    end

    it 'preserves the current session after an authentication failure' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.update_user_response = Response.new(
        status: 401, body: { 'error' => 'expired' }, headers: {}, data: nil
      )

      expect { client.auth.update_user(password: 'new-secret') }.to raise_error(
        Volcano::Error::AuthenticationError,
        'expired'
      )
      expect(client.auth.current_session).to be(established)
    end

    it 'rejects a profile returned for a replaced session' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = supplied_session
      transport.on_update_user = -> { client.auth.current_session = replacement }

      expect { client.auth.update_user(metadata: { display_name: 'Grace' }) }.to raise_error(
        Volcano::Error::SessionChangedError
      )
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#current_session=' do
    it 'stores an owned copy in an empty client' do
      supplied = supplied_session
      client.auth.current_session = supplied

      expect(client.auth.current_session).to eq(supplied)
      expect(client.auth.current_session).not_to be(supplied)
    end

    it 'owns and freezes every credential string', :aggregate_failures do
      supplied = supplied_session
      client.auth.current_session = supplied
      stored = client.auth.current_session

      expect(stored.to_h.values).to all(be_frozen)
      expect(stored.access_token).not_to be(supplied.access_token)
      expect(stored.refresh_token).not_to be(supplied.refresh_token)
      expect(stored.user_id).not_to be(supplied.user_id)
    end

    it 'cannot be changed through the supplied mutable strings' do
      supplied = supplied_session
      client.auth.current_session = supplied
      supplied.to_h.each_value { |value| value.replace('mutated') }

      expect(client.auth.current_session).to eq(
        Volcano::Session.new(
          access_token: 'adopted-access', refresh_token: 'adopted-refresh', user_id: 'adopted-user'
        )
      )
    end

    it 'replaces an existing session' do
      previous = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      supplied = supplied_session

      client.auth.current_session = supplied

      expect(client.auth.current_session).not_to be(previous)
      expect(client.auth.current_session).to eq(supplied)
    end

    {
      'a non-session value' => Object.new,
      'an empty access token' => Volcano::Session.new(access_token: ' ', refresh_token: 'r', user_id: 'u'),
      'an empty refresh token' => Volcano::Session.new(access_token: 'a', refresh_token: "\t", user_id: 'u'),
      'an empty user ID' => Volcano::Session.new(access_token: 'a', refresh_token: 'r', user_id: "\n")
    }.each do |description, invalid|
      it "rejects #{description}" do
        expect { client.auth.current_session = invalid }.to raise_error(ArgumentError)
      end
    end

    it 'preserves the previous session after rejection' do
      previous = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      invalid = Volcano::Session.new(access_token: ' ', refresh_token: 'r', user_id: 'u')

      expect { client.auth.current_session = invalid }.to raise_error(ArgumentError)
      expect(client.auth.current_session).to be(previous)
    end

    it 'does not call the transport' do
      calls_before = transport.calls.dup

      client.auth.current_session = supplied_session

      expect(transport.calls).to eq(calls_before)
    end
  end

  describe '#refresh_session' do
    it 'refreshes and owns the current session', :aggregate_failures do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')

      refreshed = client.auth.refresh_session

      expect(refreshed).to eq(
        Volcano::Session.new(
          access_token: 'access-2', refresh_token: 'refresh-2', user_id: established.user_id
        )
      )
      expect(client.auth.current_session).to be(refreshed)
      expect(refreshed.to_h.values).to all(be_frozen)
    end

    it 'rejects refresh without a session before transport' do
      expect { client.auth.refresh_session }.to raise_error(
        Volcano::Error::AuthenticationError,
        'No active session'
      )
      expect(transport.calls).to be_empty
    end

    it 'clears the captured session after a 401' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.refresh_response = Response.new(
        status: 401, body: { 'error' => 'expired' }, headers: {}, data: nil
      )

      expect { client.auth.refresh_session }.to raise_error(
        Volcano::Error::AuthenticationError,
        'expired'
      )
      expect(client.auth.current_session).to be_nil
    end

    it 'preserves the captured session after a 503' do
      established = client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.refresh_response = Response.new(
        status: 503, body: { 'error' => 'unavailable' }, headers: {}, data: nil
      )

      expect { client.auth.refresh_session }.to raise_error(Volcano::Error::ServerError, 'unavailable')
      expect(client.auth.current_session).to be(established)
    end

    it 'does not replace a session established during refresh' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = supplied_session
      transport.on_refresh = -> { client.auth.current_session = replacement }

      expect { client.auth.refresh_session }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end
  end

  describe '#sign_out' do
    it 'revokes and clears the current session' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')

      expect(client.auth.sign_out).to be_nil
      expect(client.auth.current_session).to be_nil
      expect(transport.calls_for(:auth_logout).last.fetch(1)).to eq(
        authorization: 'anon-key', refresh_token: 'refresh-token'
      )
    end

    it 'succeeds without a session or transport call' do
      expect(client.auth.sign_out).to be_nil
      expect(transport.calls).to be_empty
    end

    it 'clears locally and raises after a 503' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      transport.logout_response = Response.new(
        status: 503, body: { 'error' => 'unavailable' }, headers: {}, data: nil
      )

      expect { client.auth.sign_out }.to raise_error(Volcano::Error::ServerError, 'unavailable')
      expect(client.auth.current_session).to be_nil
    end

    it 'does not clear a session established during sign out' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      replacement = supplied_session
      transport.on_logout = -> { client.auth.current_session = replacement }

      expect { client.auth.sign_out }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.auth.current_session).to eq(replacement)
    end

    it 'preserves a revocation failure when the session changes' do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      revocation_error = nil
      transport.on_logout = -> { client.auth.current_session = supplied_session }
      transport.logout_response = Response.new(
        status: 503, body: { 'error' => 'unavailable' }, headers: {}, data: nil
      )

      expect { client.auth.sign_out }.to raise_error(Volcano::Error::SessionChangedError) do |error|
        revocation_error = error.cause
      end
      expect(revocation_error).to be_a(Volcano::Error::ServerError)
    end
  end

  it 'returns stable public values from the five facade calls', :aggregate_failures do
    expect(results.fetch(:session)).to eq(
      Volcano::Session.new(
        access_token: 'access-token',
        refresh_token: 'refresh-token',
        user_id: 'user-123'
      )
    )
    expect(client.current_session).to be(results.fetch(:session))
    expect(results.fetch(:rows)).to eq([{ 'slug' => 'a' }])
    expect(results.fetch(:uploaded)).to eq({ 'name' => 'a.txt', 'size' => 5 })
    expect(results.fetch(:downloaded)).to eq("hello\x00".b)
    expect(results.fetch(:downloaded).encoding).to eq(Encoding::BINARY)
    expect(results.fetch(:page)).to eq(
      Volcano::StoragePage.new(
        objects: [
          Volcano::StorageObject.new(
            id: '00000000-0000-4000-8000-000000000020',
            bucket_id: '00000000-0000-4000-8000-000000000030',
            name: 'avatars/a.png',
            size: 5,
            mime_type: 'image/png',
            is_public: false,
            owner_id: '00000000-0000-4000-8000-000000000010',
            etag: 'etag-1',
            metadata: { 'width' => 32, 'labels' => ['profile'] },
            created_at: Time.iso8601('2026-08-26T12:00:00Z'),
            updated_at: Time.iso8601('2026-08-26T12:01:00Z')
          )
        ],
        next_cursor: 'cursor-2'
      )
    )
    expect(results.fetch(:page).objects.first.metadata['labels']).to be_frozen
    expect(results.fetch(:removed)).to eq(['archive/a.txt', 'archive/b.txt'])
    expect(results.fetch(:removed)).to be_frozen
    expect(results.fetch(:lease)).to eq(
      Volcano::LockLease.new(
        key: 'build',
        token: results.fetch(:lease).token,
        expires_at: Time.iso8601('2026-08-26T12:00:30Z'),
        fencing_token: 7
      )
    )
    expect(results.fetch(:released)).to be_nil
  end

  it 'routes the facade calls through the contract operations', :aggregate_failures do
    lease = results.fetch(:lease)
    expect(transport.calls.map(&:first)).to eq(
      %i[
        auth_signin
        query_database_select
        upload_storage_object
        download_storage_object
        list_storage_objects
        delete_storage_object
        delete_storage_object
        acquire_project_lock
        release_project_lock
      ]
    )
    expect(transport.calls[0][1]).to eq(
      authorization: 'anon-key',
      email: 'user@example.com',
      password: 'secret'
    )
    expect(transport.calls[1][1]).to eq(
      authorization: 'access-token',
      database_name: 'main',
      body: {
        'table' => 'items',
        'filters' => [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'a' }]
      }
    )
    expect(transport.calls[2][1]).to eq(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'a.txt',
      data: "hello\x00".b
    )
    expect(transport.calls[3][1]).to eq(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'a.txt',
      byte_range: 'bytes=0-4'
    )
    expect(transport.calls[4][1]).to eq(
      authorization: 'access-token',
      bucket_name: 'assets',
      prefix: 'avatars',
      limit: 25,
      cursor: 'cursor-1'
    )
    expect(transport.calls[5..6].map(&:last)).to eq(
      [
        { authorization: 'access-token', bucket_name: 'assets', path: 'archive/a.txt' },
        { authorization: 'access-token', bucket_name: 'assets', path: 'archive/b.txt' }
      ]
    )
    expect(transport.calls[7][1]).to include(
      authorization: 'service-key',
      key: 'build',
      ttl: 30,
      token: lease.token
    )
    expect(transport.calls[8][1]).to include(
      authorization: 'service-key',
      key: 'build',
      token: lease.token
    )
  end

  it 'normalizes an empty terminal storage cursor to nil' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    transport.define_singleton_method(:list_storage_objects) do |**_arguments|
      Response.new(
        status: 200,
        body: { 'objects' => [], 'next_cursor' => '' },
        headers: {},
        data: nil
      )
    end

    expect(client.storage.from('assets').list.next_cursor).to be_nil
  end

  it 'removes one storage path and freezes the returned snapshot' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    removed = client.storage.from('assets').remove('archive/a.txt')

    expect(removed).to eq(['archive/a.txt'])
    expect(removed).to be_frozen
  end

  it 'rejects empty storage path inputs before transport' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    calls_after_sign_in = transport.calls.dup

    [[], ['']].each do |invalid_paths|
      expect { client.storage.from('assets').remove(invalid_paths) }
        .to raise_error(ArgumentError, 'storage paths must be non-empty strings')
    end
    expect(transport.calls).to eq(calls_after_sign_in)
  end

  it 'moves an object and returns its destination metadata' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    moved = client.storage.from('assets').move('drafts/a.txt', 'published/a.txt')

    expect(moved.name).to eq('published/a.txt')
    expect(transport.calls.last).to eq(
      [
        :move_storage_object,
        {
          authorization: 'access-token', bucket_name: 'assets',
          from_path: 'drafts/a.txt', to_path: 'published/a.txt'
        }
      ]
    )
  end

  it 'copies an object and returns its destination metadata' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    copied = client.storage.from('assets').copy('templates/a.txt', 'drafts/a.txt')

    expect(copied.name).to eq('drafts/a.txt')
    expect(transport.calls.last.first).to eq(:copy_storage_object)
    expect(transport.calls.last.last).to include(
      from_path: 'templates/a.txt', to_path: 'drafts/a.txt'
    )
  end

  it 'updates object visibility and returns server-confirmed metadata' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    updated = client.storage.from('assets').update_visibility('avatars/a.png', public: true)

    expect(updated).to have_attributes(
      is_public: true,
      public_url: 'https://api.test.volcano.dev/public/project/assets/avatars/a.png'
    )
    expect(transport.calls.last).to eq(
      [
        :update_storage_object_visibility,
        {
          authorization: 'access-token', bucket_name: 'assets',
          path: 'avatars/a.png', is_public: true
        }
      ]
    )
  end

  it 'rejects invalid visibility inputs before transport' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    calls_after_sign_in = transport.calls.dup

    [['', true], ['avatars/a.png', 1], ['avatars/a.png', nil]].each do |path, is_public|
      expect { client.storage.from('assets').update_visibility(path, public: is_public) }
        .to raise_error(ArgumentError)
    end
    expect(transport.calls).to eq(calls_after_sign_in)
  end

  it 'constructs an encoded public URL locally' do
    local_client = described_class.new(
      api_url: 'https://api.test.volcano.dev/',
      anon_key: anon_key_with_project_id('project-123'),
      _transport: transport
    )

    public_url = local_client.storage.from('assets').get_public_url('avatars/Ada photo.png')

    expect(public_url).to eq(
      'https://api.test.volcano.dev/public/project-123/assets/avatars/Ada%20photo.png'
    )
    expect(public_url).to be_frozen
    expect(transport.calls).to be_empty
  end

  it 'rejects invalid anon keys when constructing public URLs' do
    ['not-a-jwt', anon_key_with_project_id(nil), 'header.%%%.signature'].each do |anon_key|
      local_client = described_class.new(anon_key: anon_key, _transport: transport)

      expect { local_client.storage.from('assets').get_public_url('avatars/a.png') }
        .to raise_error(ArgumentError, /project ID/)
    end
    expect(transport.calls).to be_empty
  end

  it 'rejects an empty public URL path before transport' do
    local_client = described_class.new(
      anon_key: anon_key_with_project_id('project-123'),
      _transport: transport
    )

    expect { local_client.storage.from('assets').get_public_url('') }
      .to raise_error(ArgumentError, 'storage path must be a non-empty string')
    expect(transport.calls).to be_empty
  end

  it 'preserves a trailing separator in a public URL path' do
    local_client = described_class.new(
      anon_key: anon_key_with_project_id('project-123'),
      _transport: transport
    )

    public_url = local_client.storage.from('assets').get_public_url('folder/')

    expect(public_url).to end_with('/public/project-123/assets/folder/')
    expect(transport.calls).to be_empty
  end

  it 'rejects dot segments in a public URL path' do
    local_client = described_class.new(
      anon_key: anon_key_with_project_id('project-123'),
      _transport: transport
    )

    ['.', 'avatars/../secret.txt'].each do |path|
      expect { local_client.storage.from('assets').get_public_url(path) }
        .to raise_error(ArgumentError, /dot segments/)
    end
    expect(transport.calls).to be_empty
  end

  it 'rejects multiple public URL paths' do
    local_client = described_class.new(
      anon_key: anon_key_with_project_id('project-123'),
      _transport: transport
    )

    expect { local_client.storage.from('assets').get_public_url(%w[first.txt second.txt]) }
      .to raise_error(ArgumentError, 'storage path must be a non-empty string')
    expect(transport.calls).to be_empty
  end

  it 'keeps query chains immutable and reads the latest session at execution time' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    base = client.database('main').from('items').select('*')
    first = base.eq('slug', 'first')
    second = base.eq('slug', 'second')

    transport.access_token = 'access-token-2'
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    first.execute
    second.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:authorization] }).to eq(
      %w[access-token-2 access-token-2]
    )
    expect(query_calls.map { |_, arguments| arguments[:body]['filters'] }).to eq(
      [
        [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'first' }],
        [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'second' }]
      ]
    )
  end

  {
    neq: 'neq',
    gt: 'gt',
    gte: 'gte',
    lt: 'lt',
    lte: 'lte'
  }.each do |method_name, operator|
    it "keeps #{method_name} comparison filters immutable" do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      source = client.database('main').from('items').select('*')

      source.public_send(method_name, 'priority', 7).execute
      source.execute

      query_calls = transport.calls_for(:query_database_select)
      expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
        [
          {
            'table' => 'items',
            'filters' => [{ 'column' => 'priority', 'operator' => operator, 'value' => 7 }]
          },
          { 'table' => 'items' }
        ]
      )
    end
  end

  { like: 'like', ilike: 'ilike' }.each do |method_name, operator|
    it "keeps #{method_name} pattern filters immutable" do
      client.auth.sign_in(email: 'user@example.com', password: 'secret')
      database_name = +'main'
      table = +'items'
      selected_column = +'id'
      filter_column = +'name'
      pattern = +'%volcano%'
      source = client.database(database_name).from(table).select(selected_column)

      query = source.public_send(method_name, filter_column, pattern)
      [database_name, table, selected_column, filter_column, pattern]
        .zip(%w[other other_items other_id other_name %lava%]) { |value, replacement| value.replace(replacement) }
      query.execute

      query_calls = transport.calls_for(:query_database_select)
      expect(query_calls.map { |_, arguments| arguments[:database_name] }).to eq(['main'])
      expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
        [
          {
            'table' => 'items',
            'select' => ['id'],
            'filters' => [
              { 'column' => 'name', 'operator' => operator, 'value' => '%volcano%' }
            ]
          }
        ]
      )
    end
  end

  it 'keeps null filters immutable' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    source = client.database('main').from('items').select('*')

    source.is('deleted_at', nil).execute
    source.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
      [
        {
          'table' => 'items',
          'filters' => [{ 'column' => 'deleted_at', 'operator' => 'is', 'value' => nil }]
        },
        { 'table' => 'items' }
      ]
    )
  end

  it 'copies membership filter values' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    source = client.database('main').from('items').select('*')
    statuses = [+'draft', +'published']

    query = source.in('status', statuses)
    statuses.first.replace('review')
    statuses << 'archived'
    query.execute
    source.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
      [
        {
          'table' => 'items',
          'filters' => [
            { 'column' => 'status', 'operator' => 'in', 'value' => %w[draft published] }
          ]
        },
        { 'table' => 'items' }
      ]
    )
  end

  it 'inserts a captured row using the current session' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    values = {
      'name' => +'Volcano',
      'metadata' => { 'labels' => [+'sdk'] }
    }

    insert = client.database('main').from('items').insert(values)
    values['name'].replace('Lava')
    values['metadata']['labels'].first.replace('mutated')
    transport.access_token = 'access-token-2'
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(insert.execute).to eq(
      [{ 'name' => 'Volcano', 'metadata' => { 'labels' => ['sdk'] } }]
    )
    expect(transport.calls_for(:query_database_insert)).to eq(
      [
        [
          :query_database_insert,
          {
            authorization: 'access-token-2',
            database_name: 'main',
            body: {
              'table' => 'items',
              'values' => { 'name' => 'Volcano', 'metadata' => { 'labels' => ['sdk'] } }
            }
          }
        ]
      ]
    )
  end

  it 'updates filtered rows from captured values using the current session' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    values = { 'metadata' => { 'labels' => [+'sdk'] } }
    statuses = [+'draft', +'published']

    update = client.database('main').from('items').update(values).in('status', statuses)
    values['metadata']['labels'].first.replace('mutated')
    statuses.first.replace('review')
    statuses << 'archived'
    transport.access_token = 'access-token-2'
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(update.execute).to eq([{ 'metadata' => { 'labels' => ['sdk'] } }])
    expect(transport.calls_for(:query_database_update)).to contain_exactly(
      [
        :query_database_update,
        {
          authorization: 'access-token-2', database_name: 'main',
          body: {
            'table' => 'items', 'values' => { 'metadata' => { 'labels' => ['sdk'] } },
            'filters' => [{ 'column' => 'status', 'operator' => 'in', 'value' => %w[draft published] }]
          }
        }
      ]
    )
  end

  it 'reuses the select filter vocabulary for updates' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    update = client.database('main').from('items').update(status: 'review')

    update.eq('id', 1).neq('state', 'deleted').gt('score', 1).gte('priority', 2)
          .lt('attempts', 5).lte('rank', 10).like('name', 'Vol%').ilike('owner', 'ada%')
          .is('deleted_at', nil).execute

    filters = transport.calls_for(:query_database_update).fetch(0).fetch(1).fetch(:body).fetch('filters')
    expect(filters.map { |filter| filter.fetch('operator') }).to eq(
      %w[eq neq gt gte lt lte like ilike is]
    )
  end

  it 'preserves filters applied before update' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    client.database('main').from('items').eq('tenant_id', 'tenant-1')
          .update(status: 'published').eq('id', 'item-1').execute

    filters = transport.calls_for(:query_database_update).fetch(0).fetch(1).fetch(:body).fetch('filters')
    expect(filters).to eq(
      [
        { 'column' => 'tenant_id', 'operator' => 'eq', 'value' => 'tenant-1' },
        { 'column' => 'id', 'operator' => 'eq', 'value' => 'item-1' }
      ]
    )
  end

  it 'deletes using captured filters and the current session' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    statuses = [+'draft', +'archived']

    delete = client.database('main').from('items').eq('tenant_id', 'tenant-1')
                   .delete.in('status', statuses)
    statuses.first.replace('review')
    statuses << 'published'
    transport.access_token = 'access-token-2'
    client.auth.sign_in(email: 'user@example.com', password: 'secret')

    expect(delete.execute).to eq([{ 'id' => 'item-1' }])
    expect(transport.calls_for(:query_database_delete)).to contain_exactly(
      [
        :query_database_delete,
        {
          authorization: 'access-token-2', database_name: 'main',
          body: {
            'table' => 'items',
            'filters' => [
              { 'column' => 'tenant_id', 'operator' => 'eq', 'value' => 'tenant-1' },
              { 'column' => 'status', 'operator' => 'in', 'value' => %w[draft archived] }
            ]
          }
        }
      ]
    )
  end

  it 'keeps ordered query chains immutable' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    source = client.database('main').from('items').select('*')

    source.order('priority', ascending: false).order('id').execute
    source.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
      [
        {
          'table' => 'items',
          'order' => [
            { 'column' => 'priority', 'ascending' => false },
            { 'column' => 'id', 'ascending' => true }
          ]
        },
        { 'table' => 'items' }
      ]
    )
  end

  it 'keeps paginated query chains immutable' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    source = client.database('main').from('items').select('*')

    source.limit(10).offset(20).execute
    source.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:body] }).to eq(
      [
        { 'table' => 'items', 'limit' => 10, 'offset' => 20 },
        { 'table' => 'items' }
      ]
    )
  end
end
