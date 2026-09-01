# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'time'

RSpec.describe Volcano::Client do
  Response = Data.define(:status, :body, :headers, :data) unless const_defined?(:Response)

  def access_token_with_session_id(session_id)
    payload = [JSON.generate(session_id: session_id)].pack('m0').tr('+/', '-_').delete('=')
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

  class FakeContractTransport
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

    def query_database_select(**arguments)
      @calls << [:query_database_select, arguments]
      Response.new(status: 200, body: { 'data' => [{ 'slug' => 'a' }] }, headers: {}, data: nil)
    end

    def upload_storage_object(**arguments)
      @calls << [:upload_storage_object, arguments]
      Response.new(status: 201, body: { 'name' => 'a.txt', 'size' => 5 }, headers: {}, data: nil)
    end

    def download_storage_object(**arguments)
      @calls << [:download_storage_object, arguments]
      Response.new(status: 200, body: nil, headers: {}, data: "hello\x00".b)
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
    downloaded = client.storage.from('assets').download('a.txt')
    lease = client.locks.acquire('build', ttl: 30)
    released = client.locks.release('build', lease)
    {
      session: session,
      rows: rows,
      uploaded: uploaded,
      downloaded: downloaded,
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

  it 'routes the facade calls through the six contract operations', :aggregate_failures do
    lease = results.fetch(:lease)
    expect(transport.calls.map(&:first)).to eq(
      %i[
        auth_signin
        query_database_select
        upload_storage_object
        download_storage_object
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
      path: 'a.txt'
    )
    expect(transport.calls[4][1]).to include(
      authorization: 'service-key',
      key: 'build',
      ttl: 30,
      token: lease.token
    )
    expect(transport.calls[5][1]).to include(
      authorization: 'service-key',
      key: 'build',
      token: lease.token
    )
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
end
