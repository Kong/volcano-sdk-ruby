# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Volcano.const_get(:GeneratedTransport, false) do
  GeneratedApis = Data.define(:authentication, :database, :storage, :locks) unless const_defined?(:GeneratedApis)
  InternalGenerated = Volcano.const_get(:Generated, false) unless const_defined?(:InternalGenerated)

  class FakeGeneratedModel
    def initialize(value)
      @value = value
    end

    def to_hash
      @value
    end
  end

  module FakeEmailChangeApi
    attr_accessor :confirmed_email_change_body

    def auth_cancel_email_change_with_http_info(options = {})
      (@cancel_email_change_calls ||= []) << options
      [FakeGeneratedModel.new({}), 200, {}]
    end

    def cancel_email_change_calls
      @cancel_email_change_calls || []
    end

    def auth_confirm_email_change_with_http_info(body, options = {})
      (@confirm_email_change_calls ||= []) << [body, options]
      profile = { user: { id: 'user-123', email: 'new@example.com', status: 'active' } }
      [@confirmed_email_change_body || JSON.generate(profile), 200, {}]
    end

    def confirm_email_change_calls
      @confirm_email_change_calls || []
    end

    def auth_delete_all_my_sessions_with_http_info
      @delete_other_sessions_calls = true
      [nil, 204, {}]
    end

    def delete_other_sessions_called?
      @delete_other_sessions_calls || false
    end
  end

  class FakeAuthenticationApi
    include FakeEmailChangeApi

    attr_accessor :email_change_body
    attr_reader :anonymous_conversion_calls, :anonymous_signup_calls, :calls, :confirm_email_calls,
                :email_change_calls,
                :forgot_password_calls, :get_user_calls,
                :logout_calls, :refresh_calls,
                :resend_confirmation_calls,
                :reset_password_calls, :signup_calls, :update_user_calls

    def initialize
      @calls = []
      @confirm_email_calls = []
      @forgot_password_calls = []
      @get_user_calls = []
      @logout_calls = []
      @refresh_calls = []
      @resend_confirmation_calls = []
      @reset_password_calls = []
      @signup_calls = []
      @update_user_calls = []
    end

    def auth_signin_with_http_info(body)
      @calls << body
      [FakeGeneratedModel.new(access_token: 'token'), 200, { 'request-id' => 'auth' }]
    end

    def auth_signup_anonymous_with_http_info(options = {})
      (@anonymous_signup_calls ||= []) << options
      session = {
        access_token: 'anonymous-access',
        refresh_token: 'anonymous-refresh',
        user: { id: 'anonymous-user' }
      }
      [FakeGeneratedModel.new(session), 201, {}]
    end

    def auth_convert_anonymous_with_http_info(body, options = {})
      (@anonymous_conversion_calls ||= []) << [body, options]
      profile = {
        user: {
          id: 'anonymous-user', email: 'converted@example.com', status: 'active',
          created_at: '2026-09-01T12:00:00Z'
        }
      }
      [JSON.generate(profile), 200, {}]
    end

    def auth_request_email_change_with_http_info(body, options = {})
      (@email_change_calls ||= []) << [body, options]
      [@email_change_body || JSON.generate({}), 200, {}]
    end

    def auth_confirm_email_with_http_info(body, options = {})
      @confirm_email_calls << [body, options]
      [FakeGeneratedModel.new(message: 'Email confirmed successfully'), 200, {}]
    end

    def auth_resend_confirmation_with_http_info(body, options = {})
      @resend_confirmation_calls << [body, options]
      [FakeGeneratedModel.new(message: 'Confirmation sent'), 200, {}]
    end

    def auth_get_user_with_http_info(options = {})
      @get_user_calls << options
      profile = {
        user: {
          id: 'user-123', email: 'user@example.com', status: 'active',
          user_metadata: { display_name: 'Ada' }
        }
      }
      [JSON.generate(profile), 200, { 'request-id' => 'user' }]
    end

    def auth_signup_with_http_info(body)
      @signup_calls << body
      acknowledgement = {
        confirmation_required: true,
        message: 'Check your email to confirm your account'
      }
      [FakeGeneratedModel.new(acknowledgement), 201, { 'request-id' => 'signup' }]
    end

    def auth_forgot_password_with_http_info(body, options = {})
      @forgot_password_calls << [body, options]
      acknowledgement = { message: 'If the email exists, a password reset link has been sent.' }
      [FakeGeneratedModel.new(acknowledgement), 200, { 'request-id' => 'forgot-password' }]
    end

    def auth_reset_password_with_http_info(body, options = {})
      @reset_password_calls << [body, options]
      [FakeGeneratedModel.new(message: 'Password reset successful'), 200, {}]
    end

    def auth_update_user_with_http_info(options)
      @update_user_calls << options
      profile = {
        user: {
          id: 'user-123', email: 'user@example.com', status: 'active',
          user_metadata: { display_name: 'Grace' }, created_at: '2026-08-31T12:00:00Z'
        }
      }
      [JSON.generate(profile), 200, { 'request-id' => 'update-user' }]
    end

    def auth_refresh_with_http_info(options)
      @refresh_calls << options
      [FakeGeneratedModel.new(access_token: 'refreshed-token'), 200, { 'request-id' => 'refresh' }]
    end

    def auth_logout_with_http_info(options)
      @logout_calls << options
      [nil, 204, { 'request-id' => 'logout' }]
    end
  end

  class FakeDatabaseApi
    attr_reader :calls

    def initialize
      @calls = []
    end

    def query_database_select_with_http_info(name, body)
      @calls << [name, body]
      [FakeGeneratedModel.new(data: [{ slug: 'a' }]), 200, {}]
    end
  end

  class FakeStorageApi
    attr_reader :calls

    def initialize
      @calls = []
    end

    def upload_storage_object_with_http_info(bucket, path, file, options = {})
      file.rewind
      @calls << [:upload, bucket, path, file.read, options]
      [FakeGeneratedModel.new(name: path), 201, {}]
    end

    def download_storage_object_with_http_info(bucket, path)
      @calls << [:download, bucket, path]
      ["hello\x00".b, 200, { 'content-type' => 'application/octet-stream' }]
    end
  end

  class FakeLocksApi
    attr_reader :calls

    def initialize
      @calls = []
    end

    def acquire_project_lock_with_http_info(key, token, request_id, body)
      @calls << [:acquire, key, token, request_id, body]
      [FakeGeneratedModel.new(fencing_token: 7), 201, {}]
    end

    def release_project_lock_with_http_info(key, token, request_id)
      @calls << [:release, key, token, request_id]
      [nil, 204, {}]
    end
  end

  let(:apis) do
    GeneratedApis.new(
      authentication: FakeAuthenticationApi.new,
      database: FakeDatabaseApi.new,
      storage: FakeStorageApi.new,
      locks: FakeLocksApi.new
    )
  end
  let(:authorizations) { [] }
  let(:factory) do
    lambda do |authorization|
      authorizations << authorization
      apis
    end
  end
  let(:transport) do
    described_class.new(api_url: 'https://api.test.volcano.dev', api_factory: factory)
  end
  let(:responses) do
    {
      signup: transport.auth_signup(
        authorization: 'anon-key',
        email: 'new@example.com',
        password: 'secret',
        metadata: { display_name: 'New User' }
      ),
      auth: transport.auth_signin(
        authorization: 'anon-key',
        email: 'user@example.com',
        password: 'secret'
      ),
      refresh: transport.auth_refresh(
        authorization: 'anon-key',
        refresh_token: 'refresh-1'
      ),
      logout: transport.auth_logout(
        authorization: 'anon-key',
        refresh_token: 'refresh-1'
      ),
      database: transport.query_database_select(
        authorization: 'access-token',
        database_name: 'main',
        body: {
          'table' => 'items',
          'filters' => [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'a' }]
        }
      ),
      upload: transport.upload_storage_object(
        authorization: 'access-token',
        bucket_name: 'assets',
        path: 'a.txt',
        data: "hello\x00".b
      ),
      download: transport.download_storage_object(
        authorization: 'access-token',
        bucket_name: 'assets',
        path: 'a.txt'
      ),
      acquire: transport.acquire_project_lock(
        authorization: 'service-key',
        key: 'build',
        ttl: 30,
        token: 'ownership-token'
      ),
      release: transport.release_project_lock(
        authorization: 'service-key',
        key: 'build',
        token: 'ownership-token'
      )
    }
  end

  def download_transport(tempfile)
    storage = Object.new
    storage.define_singleton_method(:download_storage_object_with_http_info) do |_bucket, _path|
      [tempfile, 200, { 'content-type' => 'application/octet-stream' }]
    end
    empty = Object.new
    factory = lambda do |_authorization|
      GeneratedApis.new(
        authentication: empty,
        database: empty,
        storage: storage,
        locks: empty
      )
    end
    described_class.new(api_url: 'https://api.test.volcano.dev', api_factory: factory)
  end

  it 'routes only the nine POC operations through generated API classes', :aggregate_failures do
    responses
    expect(authorizations).to eq(
      %w[anon-key anon-key anon-key anon-key access-token access-token access-token service-key service-key]
    )
    expect(apis.authentication.calls.fetch(0)).to be_a(InternalGenerated::AuthSigninRequest)
    expect(apis.authentication.calls.fetch(0).to_hash).to eq(
      email: 'user@example.com',
      password: 'secret'
    )
    refresh_request = apis.authentication.refresh_calls.fetch(0).fetch(:auth_refresh_request)
    expect(refresh_request).to be_a(InternalGenerated::AuthRefreshRequest)
      .and have_attributes(refresh_token: 'refresh-1')
    expect(apis.database.calls.fetch(0).fetch(0)).to eq('main')
    expect(apis.database.calls.fetch(0).fetch(1)).to be_a(InternalGenerated::DatabaseSelectRequest)
    expect(apis.database.calls.fetch(0).fetch(1).to_hash).to eq(
      table: 'items',
      filters: [{ column: 'slug', operator: 'eq', value: 'a' }]
    )
    expect(apis.storage.calls).to eq(
      [
        [
          :upload,
          'assets',
          'a.txt',
          "hello\x00".b,
          {}
        ],
        [:download, 'assets', 'a.txt']
      ]
    )
    expect(apis.locks.calls[0][0..2]).to eq([:acquire, 'build', 'ownership-token'])
    expect(apis.locks.calls[0][3]).to match(/\A[0-9a-f-]{36}\z/)
    expect(apis.locks.calls[0][4].to_hash).to eq(ttl_seconds: 30)
    expect(apis.locks.calls[1][0..2]).to eq([:release, 'build', 'ownership-token'])
    expect(apis.locks.calls[1][3]).to match(/\A[0-9a-f-]{36}\z/)
  end

  it 'builds the generated sign-up request with metadata' do
    responses

    request = apis.authentication.signup_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthSignupRequest)
    expect(request.to_hash).to eq(
      email: 'new@example.com',
      password: 'secret',
      user_metadata: { display_name: 'New User' }
    )
  end

  it 'signs in anonymously through the generated operation' do
    response = transport.auth_signup_anonymous(
      authorization: 'anon-key', metadata: { device: 'mobile' }
    )

    options = apis.authentication.anonymous_signup_calls.fetch(0)
    request = options.fetch(:auth_signup_anonymous_request)
    expect(request).to be_a(InternalGenerated::AuthSignupAnonymousRequest)
      .and have_attributes(user_metadata: { device: 'mobile' })
    expect(response.status).to eq(201)
    expect(authorizations).to eq(['anon-key'])
  end

  it 'converts an anonymous user through the generated operation' do
    response = transport.auth_convert_anonymous(
      authorization: 'anonymous-access',
      email: 'converted@example.com',
      password: 'secret',
      metadata: { answers: [1, nil, 3] }
    )

    request, options = apis.authentication.anonymous_conversion_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthSignupRequest)
      .and have_attributes(
        email: 'converted@example.com',
        password: 'secret',
        user_metadata: { answers: [1, nil, 3] }
      )
    expect(options).to eq(
      debug_body: {
        email: 'converted@example.com', password: 'secret',
        user_metadata: { answers: [1, nil, 3] }
      },
      debug_return_type: 'String'
    )
    expect(response.status).to eq(200)
    expect(response.body.dig('user', 'created_at')).to eq('2026-09-01T12:00:00Z')
    expect(authorizations).to eq(['anonymous-access'])
  end

  it 'requests an email change through the generated operation' do
    response = transport.auth_request_email_change(
      authorization: 'access-token', new_email: 'new@example.com'
    )

    request, options = apis.authentication.email_change_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthRequestEmailChangeRequest)
      .and have_attributes(new_email: 'new@example.com')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['access-token'])
  end

  it 'cancels an email change through the generated operation' do
    response = transport.auth_cancel_email_change(authorization: 'access-token')

    expect(apis.authentication.cancel_email_change_calls).to eq([{}])
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['access-token'])
  end

  it 'confirms an email change through the generated operation' do
    response = transport.auth_confirm_email_change(
      authorization: 'access-token', token: 'change-token'
    )

    request, options = apis.authentication.confirm_email_change_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthConfirmEmailChangeRequest)
      .and have_attributes(email_change_token: 'change-token')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.body.dig('user', 'email')).to eq('new@example.com')
    expect(authorizations).to eq(['access-token'])
  end

  it 'deletes all other sessions through the generated operation' do
    response = transport.auth_delete_all_my_sessions(authorization: 'access-token')

    expect(apis.authentication.delete_other_sessions_called?).to be(true)
    expect(response.status).to eq(204)
    expect(authorizations).to eq(['access-token'])
  end

  it 'rejects a malformed email-change response' do
    apis.authentication.email_change_body = '{'

    expect do
      transport.auth_request_email_change(
        authorization: 'access-token', new_email: 'new@example.com'
      )
    end.to raise_error(TypeError, 'Expected a valid email-change acknowledgement')
  end

  it 'requests a password reset through the generated operation' do
    response = transport.auth_forgot_password(
      authorization: 'anon-key', email: 'user@example.com'
    )

    request, options = apis.authentication.forgot_password_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthForgotPasswordRequest)
      .and have_attributes(email: 'user@example.com')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.status).to eq(200)
    expect(response.body).to eq(
      'message' => 'If the email exists, a password reset link has been sent.'
    )
    expect(authorizations).to eq(['anon-key'])
  end

  it 'resets a password through the generated operation' do
    response = transport.auth_reset_password(
      authorization: 'anon-key', token: 'recovery-token', new_password: 'new-secret'
    )

    request, options = apis.authentication.reset_password_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthResetPasswordRequest)
      .and have_attributes(token: 'recovery-token', new_password: 'new-secret')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['anon-key'])
  end

  it 'confirms an email through the generated operation' do
    response = transport.auth_confirm_email(
      authorization: 'anon-key', token: 'confirmation-token'
    )

    request, options = apis.authentication.confirm_email_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthConfirmEmailRequest)
      .and have_attributes(token: 'confirmation-token')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['anon-key'])
  end

  it 'resends confirmation through the generated operation' do
    response = transport.auth_resend_confirmation(
      authorization: 'anon-key', email: 'user@example.com'
    )

    request, options = apis.authentication.resend_confirmation_calls.fetch(0)
    expect(request).to be_a(InternalGenerated::AuthForgotPasswordRequest)
      .and have_attributes(email: 'user@example.com')
    expect(options).to eq(debug_return_type: 'String')
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['anon-key'])
  end

  it 'sends the refresh token through the generated logout request' do
    transport.auth_logout(authorization: 'anon-key', refresh_token: 'refresh-1')

    request = apis.authentication.logout_calls.fetch(0).fetch(:auth_refresh_request)
    expect(request).to be_a(InternalGenerated::AuthRefreshRequest)
      .and have_attributes(refresh_token: 'refresh-1')
  end

  it 'gets the current user through the generated operation' do
    response = transport.auth_get_user(authorization: 'access-token')

    expect(apis.authentication.get_user_calls).to eq([{ debug_return_type: 'String' }])
    expect(authorizations).to eq(['access-token'])
    expect(response.status).to eq(200)
    expect(response.body.fetch('user')).to include(
      'id' => 'user-123', 'email' => 'user@example.com', 'status' => 'active'
    )
  end

  it 'updates the current user through the generated operation without lossy coercion' do
    response = transport.auth_update_user(
      authorization: 'access-token',
      password: 'new-secret',
      metadata: { display_name: 'Grace', answers: [1, nil, 3] }
    )

    options = apis.authentication.update_user_calls.fetch(0)
    request = options.fetch(:auth_update_user_request)
    expect(request).to be_a(InternalGenerated::AuthUpdateUserRequest)
    expect(options.fetch(:debug_body)).to eq(
      password: 'new-secret',
      user_metadata: { display_name: 'Grace', answers: [1, nil, 3] }
    )
    expect(options.fetch(:debug_return_type)).to eq('String')
    expect(response.body.fetch('user')).to include(
      'id' => 'user-123', 'user_metadata' => { 'display_name' => 'Grace' },
      'created_at' => '2026-08-31T12:00:00Z'
    )
    expect(authorizations).to eq(['access-token'])
  end

  it 'omits absent current-user update fields' do
    transport.auth_update_user(authorization: 'access-token', password: nil, metadata: nil)

    options = apis.authentication.update_user_calls.fetch(0)
    expect(options.fetch(:auth_update_user_request)).to be_a(
      InternalGenerated::AuthUpdateUserRequest
    )
    expect(options.fetch(:debug_body)).to be_empty
  end

  it 'parses the current-user response independently of generated content-type handling' do
    apis.authentication.define_singleton_method(:auth_get_user_with_http_info) do |options|
      raise 'generated deserializer selected' unless options.fetch(:debug_return_type) == 'String'

      body = JSON.generate(user: { id: 'user-123', email: 'user@example.com', status: 'active' })
      [body, 200, { 'Content-Type' => 'text/html' }]
    end

    response = transport.auth_get_user(authorization: 'access-token')

    expect(response.body.fetch('user')).to include('id' => 'user-123', 'status' => 'active')
  end

  it 'normalizes an empty generated user response' do
    apis.authentication.define_singleton_method(:auth_get_user_with_http_info) do |_options|
      [nil, 200, { 'Content-Type' => 'application/json' }]
    end

    expect { transport.auth_get_user(authorization: 'access-token') }.to raise_error(
      Volcano::Error::AuthenticationError,
      'Expected a complete user profile'
    ) do |error|
      expect(error.cause).to be_a(TypeError)
    end
  end

  it 'normalizes invalid JSON returned for the current user' do
    apis.authentication.define_singleton_method(:auth_get_user_with_http_info) do |_options|
      ['not-json', 200, { 'Content-Type' => 'application/json' }]
    end

    expect { transport.auth_get_user(authorization: 'access-token') }.to raise_error(
      Volcano::Error::AuthenticationError,
      'Expected a complete user profile'
    ) do |error|
      expect(error.cause).to be_a(JSON::ParserError)
    end
  end

  it 'normalizes generated responses for the facade', :aggregate_failures do
    expect(responses.fetch(:signup).body).to eq(
      'confirmation_required' => true,
      'message' => 'Check your email to confirm your account'
    )
    expect(responses.fetch(:auth).body).to eq('access_token' => 'token')
    expect(responses.fetch(:refresh).body).to eq('access_token' => 'refreshed-token')
    expect(responses.fetch(:logout).status).to eq(204)
    expect(responses.fetch(:database).body).to eq('data' => [{ 'slug' => 'a' }])
    expect(responses.fetch(:upload).body).to eq('name' => 'a.txt')
    expect(responses.fetch(:download).data).to eq("hello\x00".b)
    expect(responses.fetch(:acquire).body).to eq('fencing_token' => 7)
    expect(responses.fetch(:release).status).to eq(204)
  end

  it 'selects the multipart representation for the generated dual-mode upload operation' do
    configuration = InternalGenerated::Configuration.new
    api_client = described_class::ApiClient.new(configuration)

    expect(
      api_client.select_header_content_type(['multipart/form-data', 'application/json'])
    ).to eq('multipart/form-data')
    expect(api_client.select_header_content_type(['application/json'])).to eq('application/json')
  end

  it 'converts the public timeout in seconds to Typhoeus milliseconds' do
    transport = described_class.new(api_url: 'https://api.test.volcano.dev', timeout: 1.5)
    configuration = transport.send(:generated_configuration, 'access-token')
    request = described_class::ApiClient.new(configuration).build_request(
      :get,
      '/health',
      auth_names: []
    )

    expect(request.options.fetch(:timeout)).to eq(1_500)
  end

  it 'preserves object path segments and percent-encodes spaces' do
    configuration = InternalGenerated::Configuration.new
    api_client = described_class::ApiClient.new(configuration)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, method == :POST ? 201 : 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)
    file = Tempfile.new('volcano-storage-path')

    storage.upload_storage_object_with_http_info('assets', 'folder/payload with space.txt', file)
    storage.download_storage_object_with_http_info('assets', 'folder/payload with space.txt')

    expect(calls.map { |call| call.fetch(1) }).to eq(
      Array.new(2, '/storage/assets/folder/payload%20with%20space.txt')
    )
    expect(calls.fetch(0).fetch(2).fetch(:return_type)).to eq('StorageObject')
  ensure
    file&.close!
  end

  it 'deserializes internal models while the generated namespace is private' do
    configuration = InternalGenerated::Configuration.new
    api_client = described_class::ApiClient.new(configuration)
    response = Typhoeus::Response.new(
      code: 200,
      body: JSON.generate(email: 'user@example.com', password: 'secret'),
      headers: { 'Content-Type' => 'application/json' }
    )

    model = api_client.deserialize(response, 'AuthSigninRequest')

    expect(model).to be_a(InternalGenerated::AuthSigninRequest)
    expect(model.to_hash).to eq(email: 'user@example.com', password: 'secret')
  end

  it 'deserializes nested internal models while the generated namespace is private' do
    model = InternalGenerated::ApiModelBase._deserialize(
      'AuthUser',
      id: 'user-id', email: 'user@example.com', status: 'active'
    )

    expect(model).to be_a(InternalGenerated::AuthUser)
    expect(model.email).to eq('user@example.com')
  end

  it 'reads and removes a closed download tempfile returned by the generated client' do
    tempfile = Tempfile.new('volcano-generated-download')
    tempfile.binmode
    tempfile.write("hello\x00".b)
    path = tempfile.path
    tempfile.close
    transport = download_transport(tempfile)

    response = transport.download_storage_object(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'a.txt'
    )

    expect(response.data).to eq("hello\x00".b)
    expect(File.exist?(path)).to be(false)
  ensure
    tempfile&.close!
  end

  it 'returns generated HTTP failures for stable facade error mapping' do
    error = InternalGenerated::ApiError.new(
      code: 409,
      response_headers: { 'Retry-After' => '3' },
      response_body: '{"error":"already held","code":"lock_conflict"}'
    )
    authentication = Object.new
    authentication.define_singleton_method(:auth_signin_with_http_info) { |_| raise error }
    empty = Object.new
    factory = lambda do |_authorization|
      GeneratedApis.new(authentication: authentication, database: empty, storage: empty, locks: empty)
    end
    transport = described_class.new(api_url: 'https://api.test.volcano.dev', api_factory: factory)

    response = transport.auth_signin(
      authorization: 'anon-key',
      email: 'user@example.com',
      password: 'secret'
    )

    expect(response.status).to eq(409)
    expect(response.body).to eq('error' => 'already held', 'code' => 'lock_conflict')
    expect(response.headers).to eq('Retry-After' => '3')
  end
end
