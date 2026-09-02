# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Volcano.const_get(:GeneratedTransport, false) do
  unless const_defined?(:GeneratedApis)
    GeneratedApis = Data.define(:authentication, :oauth, :database, :storage, :locks)
  end
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

    def auth_delete_my_session_with_http_info(session_id)
      @deleted_session_id = session_id
      [nil, 204, {}]
    end

    def auth_get_my_sessions_with_http_info(options = {})
      @list_sessions_options = options
      page = {
        sessions: [], total: 21, page: 2, limit: 10, total_pages: 3
      }
      [FakeGeneratedModel.new(page), 200, {}]
    end

    def delete_other_sessions_called?
      @delete_other_sessions_calls || false
    end

    attr_reader :deleted_session_id, :list_sessions_options
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
    attr_reader :calls, :delete_calls, :insert_calls, :update_calls

    def initialize
      @calls = []
      @insert_calls = []
      @update_calls = []
      @delete_calls = []
    end

    def query_database_select_with_http_info(name, body)
      @calls << [name, body]
      [FakeGeneratedModel.new(data: [{ slug: 'a' }]), 200, {}]
    end

    def query_database_insert_with_http_info(name, body)
      @insert_calls << [name, body]
      [FakeGeneratedModel.new(data: [{ slug: 'new' }]), 200, {}]
    end

    def query_database_update_with_http_info(name, body)
      @update_calls << [name, body]
      [FakeGeneratedModel.new(data: [{ slug: 'updated' }]), 200, {}]
    end

    def query_database_delete_with_http_info(name, body)
      @delete_calls << [name, body]
      [FakeGeneratedModel.new(data: [{ slug: 'deleted' }]), 200, {}]
    end
  end

  class FakeOAuthApi
    attr_reader :api_calls, :exchange_calls, :link_calls, :list_calls, :refresh_calls,
                :token_status_calls, :unlink_calls

    def initialize
      @api_calls = []
      @exchange_calls = []
      @link_calls = []
      @list_calls = []
      @refresh_calls = []
      @token_status_calls = []
      @unlink_calls = []
    end

    def auth_o_auth_exchange_with_http_info(body)
      @exchange_calls << body
      result = {
        access_token: 'oauth-access', token_type: 'bearer', expires_in: 3600,
        refresh_token: 'oauth-refresh',
        user: { id: '00000000-0000-4000-8000-000000000010' }
      }
      [FakeGeneratedModel.new(result), 200, {}]
    end

    def auth_link_o_auth_provider_with_http_info(provider, options = {})
      @link_calls << [provider, options]
      result = { authorization_url: 'https://accounts.example/link' }
      [FakeGeneratedModel.new(result), 200, {}]
    end

    def auth_list_o_auth_providers_with_http_info(options = {})
      @list_calls << options
      providers = {
        providers: [
          {
            provider: 'google',
            linked_at: Time.iso8601('2026-08-30T12:00:00Z'),
            updated_at: Time.iso8601('2026-09-01T12:00:00Z')
          }
        ]
      }
      [FakeGeneratedModel.new(providers), 200, {}]
    end

    def auth_unlink_o_auth_provider_with_http_info(provider)
      @unlink_calls << provider
      [nil, 204, {}]
    end

    def get_o_auth_provider_token_with_http_info(provider)
      @token_status_calls << provider
      result = {
        message: 'Provider token is valid', provider: provider, expires_in: 3600
      }
      [FakeGeneratedModel.new(result), 200, {}]
    end

    def refresh_o_auth_provider_token_with_http_info(provider)
      @refresh_calls << provider
      result = {
        message: 'Provider token refreshed successfully', provider: provider, expires_in: 3600
      }
      [FakeGeneratedModel.new(result), 200, {}]
    end

    def call_o_auth_provider_api_with_http_info(provider, request)
      @api_calls << [provider, request]
      result = {
        provider: provider, endpoint: request.endpoint, status_code: 200,
        data: [{ name: 'volcano' }, nil]
      }
      [FakeGeneratedModel.new(result), 200, {}]
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

    def download_storage_object_with_http_info(bucket, path, options = {})
      @calls << [:download, bucket, path, options]
      ["hello\x00".b, 200, { 'content-type' => 'application/octet-stream' }]
    end

    def create_upload_session_with_http_info(bucket, path, request)
      @calls << [:create_session, bucket, path, request]
      session = FakeGeneratedModel.new(
        session_id: 'session-123', part_size: 8_388_608, total_parts: 3,
        expires_at: Time.iso8601('2026-09-09T12:00:00Z')
      )
      [session, 201, {}]
    end

    def upload_part_with_http_info(bucket, path, session_id, part_number, data)
      @calls << [:upload_part, bucket, path, session_id, part_number, data]
      [FakeGeneratedModel.new(part_number: part_number, etag: 'etag-part', size: data.bytesize), 200, {}]
    end

    def complete_upload_session_with_http_info(bucket, path, session_id)
      @calls << [:complete_upload_session, bucket, path, session_id]
      object = FakeGeneratedModel.new(
        id: 'object-123', bucket_id: 'bucket-123', name: path, size: 20_000_000,
        mime_type: 'video/mp4', is_public: false
      )
      [FakeGeneratedModel.new(object: object), 200, {}]
    end

    def get_upload_session_with_http_info(bucket, path, session_id)
      @calls << [:get_upload_session, bucket, path, session_id]
      status = FakeGeneratedModel.new(
        session_id: session_id, status: 'uploading', path: path, content_type: 'video/mp4',
        total_size: 20_000_000, part_size: 8_388_608, total_parts: 3,
        parts_uploaded: 1, bytes_uploaded: 8_388_608, parts: [],
        expires_at: Time.iso8601('2026-09-09T12:00:00Z'),
        created_at: Time.iso8601('2026-09-02T12:00:00Z')
      )
      [status, 200, {}]
    end

    def abort_upload_session_with_http_info(bucket, path, session_id)
      @calls << [:abort_upload_session, bucket, path, session_id]
      [nil, 200, {}]
    end

    def list_storage_objects_with_http_info(bucket, options)
      @calls << [:list, bucket, options]
      page = FakeGeneratedModel.new(objects: [], next_cursor: 'cursor-2')
      [page, 200, {}]
    end

    def delete_storage_object_with_http_info(bucket, path)
      @calls << [:delete, bucket, path]
      [nil, 200, {}]
    end

    def move_storage_object_with_http_info(bucket, request)
      @calls << [:move, bucket, request]
      [FakeGeneratedModel.new(name: request.to), 200, {}]
    end

    def copy_storage_object_with_http_info(bucket, request)
      @calls << [:copy, bucket, request]
      [FakeGeneratedModel.new(name: request.to), 201, {}]
    end

    def update_storage_object_visibility_with_http_info(bucket, path, request)
      @calls << [:visibility, bucket, path, request]
      [FakeGeneratedModel.new(name: path, is_public: request.is_public), 200, {}]
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

    def get_project_lock_with_http_info(key, request_id)
      @calls << [:get, key, request_id]
      state = FakeGeneratedModel.new(
        held: true,
        expires_at: Time.iso8601('2026-08-26T12:00:30Z'),
        fencing_token: 7
      )
      [state, 200, {}]
    end
  end

  let(:apis) do
    GeneratedApis.new(
      authentication: FakeAuthenticationApi.new,
      oauth: FakeOAuthApi.new,
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
      insert: transport.query_database_insert(
        authorization: 'access-token',
        database_name: 'main',
        body: { 'table' => 'items', 'values' => { 'slug' => 'new' } }
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
        path: 'a.txt',
        byte_range: 'bytes=0-4'
      ),
      list: transport.list_storage_objects(
        authorization: 'access-token',
        bucket_name: 'assets',
        prefix: 'avatars',
        limit: 25,
        cursor: 'cursor-1'
      ),
      delete: transport.delete_storage_object(
        authorization: 'access-token',
        bucket_name: 'assets',
        path: 'archive/a.txt'
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
    storage.define_singleton_method(:download_storage_object_with_http_info) do |_bucket, _path, _options|
      [tempfile, 200, { 'content-type' => 'application/octet-stream' }]
    end
    empty = Object.new
    factory = lambda do |_authorization|
      GeneratedApis.new(
        authentication: empty,
        oauth: empty,
        database: empty,
        storage: storage,
        locks: empty
      )
    end
    described_class.new(api_url: 'https://api.test.volcano.dev', api_factory: factory)
  end

  it 'reads a lock through the generated API' do
    response = transport.get_project_lock(authorization: 'service-key', key: 'build:queue')

    expect(response.body).to eq(
      'held' => true,
      'expires_at' => Time.iso8601('2026-08-26T12:00:30Z'),
      'fencing_token' => 7
    )
    operation, key, request_id = apis.locks.calls.last
    expect([operation, key]).to eq([:get, 'build:queue'])
    expect(request_id).to match(/\A[0-9a-f-]{36}\z/)
    expect(authorizations).to eq(['service-key'])
  end

  it 'routes only the ten POC operations through generated API classes', :aggregate_failures do
    responses
    expected_authorizations = Array.new(4, 'anon-key') + Array.new(6, 'access-token') + Array.new(2, 'service-key')
    expect(authorizations).to eq(expected_authorizations)
    expect(apis.authentication.calls.fetch(0)).to be_a(InternalGenerated::AuthSigninRequest)
    expect(apis.authentication.calls.fetch(0).to_hash).to eq(
      email: 'user@example.com',
      password: 'secret'
    )
    refresh_request = apis.authentication.refresh_calls.fetch(0).fetch(:auth_refresh_request)
    expect(refresh_request).to be_a(InternalGenerated::AuthRefreshRequest)
      .and have_attributes(refresh_token: 'refresh-1')
    expect(apis.storage.calls).to eq(
      [
        [
          :upload,
          'assets',
          'a.txt',
          "hello\x00".b,
          {}
        ],
        [:download, 'assets', 'a.txt', { range: 'bytes=0-4' }],
        [:list, 'assets', { prefix: 'avatars', limit: 25, cursor: 'cursor-1' }],
        [:delete, 'assets', 'archive/a.txt']
      ]
    )
    expect(apis.locks.calls[0][0..2]).to eq([:acquire, 'build', 'ownership-token'])
    expect(apis.locks.calls[0][3]).to match(/\A[0-9a-f-]{36}\z/)
    expect(apis.locks.calls[0][4].to_hash).to eq(ttl_seconds: 30)
    expect(apis.locks.calls[1][0..2]).to eq([:release, 'build', 'ownership-token'])
    expect(apis.locks.calls[1][3]).to match(/\A[0-9a-f-]{36}\z/)
  end

  it 'builds selects with the generated database request model' do
    responses
    database_name, request = apis.database.calls.fetch(0)

    expect(database_name).to eq('main')
    expect(request).to be_a(InternalGenerated::DatabaseSelectRequest)
    expect(request.to_hash).to eq(
      table: 'items',
      filters: [{ column: 'slug', operator: 'eq', value: 'a' }]
    )
  end

  it 'builds inserts with the generated database request model' do
    responses
    database_name, request = apis.database.insert_calls.fetch(0)

    expect(database_name).to eq('main')
    expect(request).to be_a(InternalGenerated::DatabaseInsertRequest)
    expect(request.to_hash).to eq(table: 'items', values: { slug: 'new' })
  end

  it 'builds moves with the generated storage request model' do
    response = transport.move_storage_object(
      authorization: 'access-token',
      bucket_name: 'assets',
      from_path: 'drafts/a.txt',
      to_path: 'published/a.txt'
    )

    _, bucket, request = apis.storage.calls.last
    expect(bucket).to eq('assets')
    expect(request).to be_a(InternalGenerated::StorageMoveRequest)
    expect(request.to_hash).to eq(from: 'drafts/a.txt', to: 'published/a.txt')
    expect(response.body).to eq('name' => 'published/a.txt')
  end

  it 'builds copies with the generated storage request model' do
    response = transport.copy_storage_object(
      authorization: 'access-token',
      bucket_name: 'assets',
      from_path: 'templates/a.txt',
      to_path: 'drafts/a.txt'
    )

    _, bucket, request = apis.storage.calls.last
    expect(bucket).to eq('assets')
    expect(request).to be_a(InternalGenerated::StorageCopyRequest)
    expect(request.to_hash).to eq(from: 'templates/a.txt', to: 'drafts/a.txt')
    expect(response.body).to eq('name' => 'drafts/a.txt')
  end

  it 'builds visibility updates with the generated storage request model' do
    response = transport.update_storage_object_visibility(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'avatars/a.png',
      is_public: true
    )

    _, bucket, path, request = apis.storage.calls.last
    expect(bucket).to eq('assets')
    expect(path).to eq('avatars/a.png')
    expect(request).to be_a(InternalGenerated::StorageVisibilityRequest)
    expect(request.to_hash).to eq(is_public: true)
    expect(response.body).to eq('name' => 'avatars/a.png', 'is_public' => true)
  end

  it 'builds updates with the generated database request model' do
    response = transport.query_database_update(
      authorization: 'access-token', database_name: 'main',
      body: {
        'table' => 'items', 'values' => { 'slug' => 'updated' },
        'filters' => [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'new' }]
      }
    )
    database_name, request = apis.database.update_calls.fetch(0)

    expect(response.body).to eq('data' => [{ 'slug' => 'updated' }])
    expect(database_name).to eq('main')
    expect(request).to be_a(InternalGenerated::DatabaseUpdateRequest)
    expect(request.to_hash).to eq(
      table: 'items', values: { slug: 'updated' },
      filters: [{ column: 'slug', operator: 'eq', value: 'new' }]
    )
  end

  it 'builds deletes with the generated database request model' do
    response = transport.query_database_delete(
      authorization: 'access-token', database_name: 'main',
      body: {
        'table' => 'items',
        'filters' => [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'old' }]
      }
    )
    database_name, request = apis.database.delete_calls.fetch(0)

    expect(response.body).to eq('data' => [{ 'slug' => 'deleted' }])
    expect(database_name).to eq('main')
    expect(request).to be_a(InternalGenerated::DatabaseDeleteRequest)
    expect(request.to_hash).to eq(
      table: 'items', filters: [{ column: 'slug', operator: 'eq', value: 'old' }]
    )
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

  it 'lists sessions through the generated operation' do
    response = transport.auth_get_my_sessions(
      authorization: 'access-token', page: 2, limit: 10
    )

    expect(apis.authentication.list_sessions_options).to eq(page: 2, limit: 10)
    expect(response.body).to include(
      'sessions' => [], 'total' => 21, 'page' => 2, 'limit' => 10, 'total_pages' => 3
    )
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['access-token'])
  end

  it 'lists linked OAuth providers through the generated operation' do
    response = transport.auth_list_oauth_providers(authorization: 'access-token')

    expect(apis.oauth.list_calls).to eq([{}])
    expect(response.body).to eq(
      'providers' => [
        {
          'provider' => 'google',
          'linked_at' => Time.iso8601('2026-08-30T12:00:00Z'),
          'updated_at' => Time.iso8601('2026-09-01T12:00:00Z')
        }
      ]
    )
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['access-token'])
  end

  it 'builds an OAuth sign-in URL through the generated operation' do
    url = described_class.new(api_url: 'https://api.test.volcano.dev')
                         .auth_oauth_authorization_url(
                           anon_key: 'anon key', provider: 'github',
                           redirect_url: 'https://app.example.test/callback?next=/projects',
                           client_state: 'state-value'
                         )
    uri = URI(url)

    expect(uri.path).to eq('/auth/oauth/github/authorize')
    expect(URI.decode_www_form(uri.query).to_h).to eq(
      'anon_key' => 'anon key',
      'redirect_url' => 'https://app.example.test/callback?next=/projects',
      'client_state' => 'state-value', 'response_mode' => 'code'
    )
  end

  it 'exchanges an OAuth code through the generated operation' do
    response = transport.auth_oauth_exchange(
      authorization: 'anon-key', code: 'oauth-code',
      redirect_url: 'https://app.example.test/callback'
    )

    expect(apis.oauth.exchange_calls.last).to have_attributes(
      code: 'oauth-code', redirect_url: 'https://app.example.test/callback'
    )
    expect(response.body).to include(
      'access_token' => 'oauth-access', 'refresh_token' => 'oauth-refresh'
    )
    expect(authorizations).to include('anon-key')
  end

  it 'starts linking an OAuth provider through the generated operation' do
    response = transport.auth_link_oauth_provider(
      authorization: 'access-token', provider: 'github'
    )

    expect(apis.oauth.link_calls).to eq([['github', {}]])
    expect(response.body).to eq(
      'authorization_url' => 'https://accounts.example/link'
    )
    expect(response.status).to eq(200)
    expect(authorizations).to eq(['access-token'])
  end

  it 'unlinks an OAuth provider through the generated operation' do
    response = transport.auth_unlink_oauth_provider(
      authorization: 'access-token', provider: 'github'
    )

    expect(apis.oauth.unlink_calls).to eq(['github'])
    expect(response.status).to eq(204)
    expect(authorizations).to eq(['access-token'])
  end

  it 'gets OAuth provider token status through the generated operation' do
    response = transport.auth_get_oauth_provider_token(
      authorization: 'access-token', provider: 'google'
    )

    expect(response.status).to eq(200)
    expect(apis.oauth.token_status_calls).to eq(['google'])
    expect(response.body).to eq(
      'message' => 'Provider token is valid', 'provider' => 'google', 'expires_in' => 3600
    )
  end

  it 'refreshes an OAuth provider token through the generated operation' do
    response = transport.auth_refresh_oauth_provider_token(
      authorization: 'access-token', provider: 'google'
    )

    expect(response.status).to eq(200)
    expect(apis.oauth.refresh_calls).to eq(['google'])
    expect(response.body).to eq(
      'message' => 'Provider token refreshed successfully',
      'provider' => 'google',
      'expires_in' => 3600
    )
  end

  it 'calls an OAuth provider API through the generated operation' do
    response = transport.auth_call_oauth_api(
      authorization: 'access-token', provider: 'github', endpoint: '/user/repos',
      method: 'POST', body: { 'items' => [1, nil, 2] }
    )

    provider, request = apis.oauth.api_calls.last
    expect(provider).to eq('github')
    expect(request).to have_attributes(
      endpoint: '/user/repos', method: 'POST', body: { 'items' => [1, nil, 2] }
    )
    expect(request.to_hash.dig(:body, 'items')).to eq([1, nil, 2])
    expect(response.body).to eq(
      'provider' => 'github', 'endpoint' => '/user/repos', 'status_code' => 200,
      'data' => [{ 'name' => 'volcano' }, nil]
    )
  end

  it 'deletes one session through the generated operation' do
    response = transport.auth_delete_my_session(
      authorization: 'access-token',
      session_id: '00000000-0000-4000-8000-000000000099'
    )

    expect(apis.authentication.deleted_session_id).to eq(
      '00000000-0000-4000-8000-000000000099'
    )
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

  it 'creates an upload session through the stable transport' do
    response = transport.create_upload_session(
      authorization: 'access-token', bucket_name: 'assets',
      request: Volcano.const_get(:UploadSessionRequest, false).new(
        path: 'videos/demo.mp4', content_type: 'video/mp4',
        total_size: 20_000_000, part_size: 8_388_608
      )
    )

    expect(response.body).to include(
      'session_id' => 'session-123', 'part_size' => 8_388_608, 'total_parts' => 3
    )
    operation, bucket, path, request = apis.storage.calls.last
    expect([operation, bucket, path]).to eq([:create_session, 'assets', 'videos/demo.mp4'])
    expect(request).to have_attributes(
      object_path: 'videos/demo.mp4', content_type: 'video/mp4',
      total_size: 20_000_000, part_size: 8_388_608
    )
  end

  it 'uploads a part through the stable transport' do
    response = transport.upload_part(
      authorization: 'access-token', bucket_name: 'assets',
      request: Volcano.const_get(:UploadPartRequest, false).new(
        path: 'videos/demo.mp4', session_id: 'session-123', part_number: 2, data: "chunk\x00".b
      )
    )

    expect(response.body).to eq('part_number' => 2, 'etag' => 'etag-part', 'size' => 6)
    expect(apis.storage.calls.last).to eq(
      [:upload_part, 'assets', 'videos/demo.mp4', 'session-123', 2, "chunk\x00".b]
    )
  end

  it 'completes an upload session through the stable transport' do
    response = transport.complete_upload_session(
      authorization: 'access-token', bucket_name: 'assets',
      request: Volcano.const_get(:UploadSessionReference, false).new(
        path: 'videos/demo.mp4', session_id: 'session-123'
      )
    )

    expect(response.body.fetch('object')).to include('name' => 'videos/demo.mp4')
    expect(apis.storage.calls.last).to eq(
      [:complete_upload_session, 'assets', 'videos/demo.mp4', 'session-123']
    )
  end

  it 'gets upload session status through the stable transport' do
    response = transport.get_upload_session(
      authorization: 'access-token', bucket_name: 'assets',
      request: Volcano.const_get(:UploadSessionReference, false).new(
        path: 'videos/demo.mp4', session_id: 'session-123'
      )
    )

    expect(response.body).to include('session_id' => 'session-123', 'status' => 'uploading')
    expect(apis.storage.calls.last).to eq(
      [:get_upload_session, 'assets', 'videos/demo.mp4', 'session-123']
    )
  end

  it 'aborts an upload session through the stable transport' do
    response = transport.abort_upload_session(
      authorization: 'access-token', bucket_name: 'assets',
      request: Volcano.const_get(:UploadSessionReference, false).new(
        path: 'videos/demo.mp4', session_id: 'session-123'
      )
    )

    expect(response.status).to eq(200)
    expect(apis.storage.calls.last).to eq(
      [:abort_upload_session, 'assets', 'videos/demo.mp4', 'session-123']
    )
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
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, method == :POST ? 201 : 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)
    file = Tempfile.new('volcano-storage-path')

    storage.upload_storage_object_with_http_info('assets', 'folder/payload with space.txt', file)
    storage.download_storage_object_with_http_info('assets', 'folder/payload with space.txt')
    storage.delete_storage_object_with_http_info('assets', 'folder/payload with space.txt')

    expected_paths = Array.new(3, '/storage/assets/folder/payload%20with%20space.txt')
    expect(calls.map { |call| call.fetch(1) }).to eq(expected_paths)
  ensure
    file&.close!
  end

  it 'maps the generated download range option to the request header' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    api_client.define_singleton_method(:call_api) { |_method, _path, options| [options, 206, {}] }
    storage = described_class::StorageApi.new(api_client)

    options, = storage.download_storage_object_with_http_info('assets', 'payload.txt', range: 'bytes=0-4')

    expect(options.fetch(:header_params).fetch('Range')).to eq('bytes=0-4')
  end

  it 'serializes upload session creation as JSON through the path adapter' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    api_client.define_singleton_method(:call_api) { |_method, _path, options| [options, 201, {}] }
    storage = described_class::StorageApi.new(api_client)
    request = InternalGenerated::CreateUploadSessionRequest.new(
      object_path: 'videos/demo.mp4', content_type: 'video/mp4', total_size: 20_000_000
    )

    options, = storage.create_upload_session_with_http_info('assets', 'videos/demo.mp4', request)

    expect(options.fetch(:header_params).fetch('Content-Type')).to eq('application/json')
    expect(JSON.parse(options.fetch(:body))).to eq(
      'object_path' => 'videos/demo.mp4',
      'content_type' => 'video/mp4',
      'total_size' => 20_000_000
    )
    expect(options.fetch(:return_type)).to eq('CreateUploadSessionResponse')
  end

  it 'sends upload parts as binary through the path adapter' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)

    storage.upload_part_with_http_info(
      'assets', 'videos/demo clip.mp4', 'session-123', 2, "chunk\x00".b
    )

    method, path, options = calls.fetch(0)
    expect([method, path]).to eq([:PUT, '/storage/assets/videos/demo%20clip.mp4'])
    expect(options.fetch(:header_params)).to include(
      'Content-Type' => 'application/octet-stream',
      'X-Upload-Session' => 'session-123',
      'X-Part-Number' => '2'
    )
    expect(options.fetch(:body)).to eq("chunk\x00".b)
    expect(options.fetch(:return_type)).to eq('UploadSessionPart')
  end

  it 'completes upload sessions through the path adapter' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)

    storage.complete_upload_session_with_http_info(
      'assets', 'videos/demo clip.mp4', 'session-123'
    )

    method, path, options = calls.fetch(0)
    expect([method, path]).to eq([:POST, '/storage/assets/videos/demo%20clip.mp4'])
    expect(options.fetch(:header_params)).to include(
      'Content-Type' => 'application/json',
      'X-Upload-Session' => 'session-123',
      'X-Upload-Complete' => 'true'
    )
    expect(JSON.parse(options.fetch(:body))).to eq({})
    expect(options.fetch(:return_type)).to eq('CompleteUploadSessionResponse')
  end

  it 'gets upload session status through the path adapter' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)

    storage.get_upload_session_with_http_info(
      'assets', 'videos/demo clip.mp4', 'session-123'
    )

    method, path, options = calls.fetch(0)
    expect([method, path]).to eq([:GET, '/storage/assets/videos/demo%20clip.mp4'])
    expect(options.fetch(:header_params)).to include(
      'Accept' => 'application/json', 'X-Upload-Session' => 'session-123'
    )
    expect(options.fetch(:return_type)).to eq('UploadSessionStatusResponse')
  end

  it 'aborts upload sessions through the path adapter' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)

    storage.abort_upload_session_with_http_info(
      'assets', 'videos/demo clip.mp4', 'session-123'
    )

    method, path, options = calls.fetch(0)
    expect([method, path]).to eq([:DELETE, '/storage/assets/videos/demo%20clip.mp4'])
    expect(options.fetch(:header_params)).to include(
      'Accept' => 'application/json', 'X-Upload-Session' => 'session-123'
    )
  end

  it 'preserves nested object paths when updating visibility' do
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, 200, {}]
    end
    storage = described_class::StorageApi.new(api_client)
    request = InternalGenerated::StorageVisibilityRequest.new(is_public: true)

    storage.update_storage_object_visibility_with_http_info(
      'assets', 'folder/payload with space.txt', request
    )

    expect(calls.fetch(0).first(2)).to eq(
      [:PATCH, '/storage/assets/folder/payload%20with%20space.txt/visibility']
    )
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
      GeneratedApis.new(
        authentication: authentication, oauth: empty, database: empty, storage: empty, locks: empty
      )
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
