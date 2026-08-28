# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Volcano.const_get(:GeneratedTransport, false) do
  unless const_defined?(:GeneratedApis)
    GeneratedApis = Data.define(:authentication, :database, :storage, :locks, :oauth) do
      def initialize(authentication:, database:, storage:, locks:, oauth: nil)
        super
      end
    end
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

  class RecordingAuthApi
    attr_reader :calls

    def initialize
      @calls = []
    end

    def method_missing(name, *arguments)
      return super unless name.end_with?('_with_http_info')

      @calls << [name, arguments]
      [FakeGeneratedModel.new(ok: true), name.to_s.include?('delete') ? 204 : 200, {}]
    end

    def respond_to_missing?(name, include_private = false)
      name.end_with?('_with_http_info') || super
    end
  end

  class FakeAuthenticationApi
    attr_reader :calls

    def initialize
      @calls = []
    end

    def auth_signin_with_http_info(body)
      @calls << body
      [FakeGeneratedModel.new(access_token: 'token'), 200, { 'request-id' => 'auth' }]
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
      auth: transport.auth_signin(
        authorization: 'anon-key',
        email: 'user@example.com',
        password: 'secret'
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

  def normalized_lock_calls
    apis.locks.calls.map do |operation, key, token, request_id, body|
      [operation, key, token, request_id.match?(/\A[0-9a-f-]{36}\z/), body&.to_hash]
    end
  end

  def recording_storage_api
    api_client = described_class::ApiClient.new(InternalGenerated::Configuration.new)
    calls = []
    api_client.define_singleton_method(:call_api) do |method, path, options|
      calls << [method, path, options]
      [nil, method == :POST ? 201 : 200, {}]
    end
    [described_class::StorageApi.new(api_client), calls]
  end

  def auth_surface_transport
    authentication = RecordingAuthApi.new
    oauth = RecordingAuthApi.new
    empty = Object.new
    factory = lambda do |_authorization|
      GeneratedApis.new(authentication:, oauth:, database: empty, storage: empty, locks: empty)
    end
    transport = described_class.new(api_url: 'https://api.test.volcano.dev', api_factory: factory)
    [transport, authentication, oauth]
  end

  it 'routes only the six POC operations through generated API classes', :aggregate_failures do
    responses
    expect(authorizations).to eq(
      %w[anon-key access-token access-token access-token service-key service-key]
    )
    expect(apis.authentication.calls.fetch(0)).to be_a(InternalGenerated::AuthSigninRequest)
    expect(apis.authentication.calls.fetch(0).to_hash).to eq(
      email: 'user@example.com',
      password: 'secret'
    )
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
    expect(normalized_lock_calls).to eq(
      [
        [:acquire, 'build', 'ownership-token', true, { ttl_seconds: 30 }],
        [:release, 'build', 'ownership-token', true, nil]
      ]
    )
  end

  it 'normalizes generated responses for the facade', :aggregate_failures do
    expect(responses.fetch(:auth).body).to eq('access_token' => 'token')
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
    storage, calls = recording_storage_api
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

  it 'routes the complete authentication surface through generated APIs' do
    transport, authentication, oauth = auth_surface_transport
    common = { authorization: 'credential' }

    [
      lambda {
        transport.auth_signup(**common, email: 'user@example.com', password: 'password', user_metadata: { 'a' => 1 })
      },
      -> { transport.auth_refresh(**common, refresh_token: 'refresh') },
      -> { transport.auth_logout(**common, refresh_token: 'refresh') },
      -> { transport.auth_get_user(**common) },
      -> { transport.auth_update_user(**common, password: 'next', user_metadata: { 'a' => 2 }) },
      -> { transport.auth_signup_anonymous(**common, user_metadata: { 'guest' => true }) },
      -> { transport.auth_convert_anonymous(**common, email: 'user@example.com', password: 'password') },
      -> { transport.auth_confirm_email(**common, token: 'confirmation') },
      -> { transport.auth_resend_confirmation(**common, email: 'user@example.com') },
      -> { transport.auth_forgot_password(**common, email: 'user@example.com') },
      -> { transport.auth_reset_password(**common, token: 'recovery', new_password: 'next') },
      -> { transport.auth_request_email_change(**common, new_email: 'next@example.com') },
      -> { transport.auth_confirm_email_change(**common, email_change_token: 'change') },
      -> { transport.auth_cancel_email_change(**common) },
      -> { transport.auth_get_my_sessions(**common, page: 2, limit: 10) },
      -> { transport.auth_delete_my_session(**common, session_id: 'session-id') },
      -> { transport.auth_delete_all_my_sessions(**common) }
    ].each(&:call)
    [
      lambda {
        transport.auth_oauth_authorize(**common, provider: 'github', redirect_url: 'https://app.test/callback',
                                                 state: 'state')
      },
      -> { transport.auth_oauth_exchange(**common, code: 'code', redirect_url: 'https://app.test/callback') },
      lambda {
        transport.auth_link_oauth_provider(**common, provider: 'github', redirect_url: 'https://app.test/link',
                                                     state: 'state')
      },
      -> { transport.auth_unlink_oauth_provider(**common, provider: 'github') },
      -> { transport.auth_list_oauth_providers(**common) },
      -> { transport.refresh_oauth_provider_token(**common, provider: 'github') },
      -> { transport.get_oauth_provider_token(**common, provider: 'github') },
      lambda {
        transport.call_oauth_provider_api(**common, provider: 'github', endpoint: '/user', method: 'POST',
                                                    body: { 'a' => 1 })
      }
    ].each(&:call)

    expect(authentication.calls.map(&:first)).to eq(
      %i[
        auth_signup_with_http_info auth_refresh_with_http_info auth_logout_with_http_info
        auth_get_user_with_http_info auth_update_user_with_http_info
        auth_signup_anonymous_with_http_info auth_convert_anonymous_with_http_info
        auth_confirm_email_with_http_info auth_resend_confirmation_with_http_info
        auth_forgot_password_with_http_info auth_reset_password_with_http_info
        auth_request_email_change_with_http_info auth_confirm_email_change_with_http_info
        auth_cancel_email_change_with_http_info auth_get_my_sessions_with_http_info
        auth_delete_my_session_with_http_info auth_delete_all_my_sessions_with_http_info
      ]
    )
    expect(oauth.calls.map(&:first)).to eq(
      %i[
        auth_o_auth_authorize_with_http_info auth_o_auth_exchange_with_http_info
        auth_link_o_auth_provider_with_http_info auth_unlink_o_auth_provider_with_http_info
        auth_list_o_auth_providers_with_http_info refresh_o_auth_provider_token_with_http_info
        get_o_auth_provider_token_with_http_info call_o_auth_provider_api_with_http_info
      ]
    )
    expect(authentication.calls[0][1][0]).to be_a(InternalGenerated::AuthSignupRequest)
    expect(oauth.calls[-1][1][1]).to be_a(InternalGenerated::CallOAuthProviderAPIRequest)
  end
end
