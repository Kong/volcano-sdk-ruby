# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'tempfile'
require 'uri'

generated_load_path = File.expand_path('generated/lib', __dir__)
$LOAD_PATH.unshift(generated_load_path) unless $LOAD_PATH.include?(generated_load_path)
require 'volcano-generated'

generated_namespace = Volcano.const_get(:Generated, false)
generated_namespace.constants(false).each do |name|
  generated_namespace.const_get(name, false)
end

module Volcano
  private_constant :Generated

  class GeneratedTransport
    GeneratedApis = Data.define(:authentication, :database, :storage, :locks)

    module ModelDeserialization
      def _deserialize(type, value)
        super
      rescue NameError => e
        raise unless e.name == :Generated && e.message.include?('private constant Volcano::Generated')

        klass = Generated.const_get(type)
        if klass.respond_to?(:openapi_any_of) || klass.respond_to?(:openapi_one_of)
          klass.build(value)
        else
          klass.build_from_hash(value)
        end
      end
    end
    private_constant :ModelDeserialization

    Generated::ApiModelBase.singleton_class.prepend(ModelDeserialization)

    class ApiClient < Generated::ApiClient
      def select_header_content_type(content_types)
        if content_types.include?('multipart/form-data') && content_types.include?('application/json')
          return 'multipart/form-data'
        end

        super
      end

      def convert_to_type(data, return_type)
        super
      rescue NameError => e
        raise unless e.name == :Generated && e.message.include?('private constant Volcano::Generated')

        klass = Generated.const_get(return_type)
        klass.respond_to?(:openapi_one_of) ? klass.build(data) : klass.build_from_hash(data)
      end
    end

    def initialize(api_url:, timeout: 60, api_factory: nil)
      @api_url = api_url
      @timeout = timeout
      @api_factory = api_factory || method(:build_apis)
    end

    def auth_signin(authorization:, email:, password:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.authentication.auth_signin_with_http_info(
          Generated::AuthSigninRequest.new(email: email, password: password)
        )
        response(data, status, headers)
      end
    end

    def query_database_select(authorization:, database_name:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::DatabaseSelectRequest.new(deep_symbolize(body))
        data, status, headers = apis.database.query_database_select_with_http_info(
          database_name,
          request
        )
        response(data, status, headers)
      end
    end

    def upload_storage_object(authorization:, bucket_name:, path:, data:)
      invoke do
        apis = @api_factory.call(authorization)
        Tempfile.create(['volcano-sdk-upload', File.extname(path)], binmode: true) do |file|
          file.write(data)
          file.flush
          data_value, status, headers = apis.storage.upload_storage_object_with_http_info(
            bucket_name,
            path,
            file
          )
          return response(data_value, status, headers)
        end
      end
    end

    def download_storage_object(authorization:, bucket_name:, path:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.download_storage_object_with_http_info(bucket_name, path)
        response(nil, status, headers, binary: binary_data(data))
      end
    end

    def acquire_project_lock(authorization:, key:, ttl:, token:)
      invoke do
        apis = @api_factory.call(authorization)
        body = Generated::ProjectLockLeaseRequest.new(ttl_seconds: ttl)
        data, status, headers = apis.locks.acquire_project_lock_with_http_info(
          key,
          token,
          SecureRandom.uuid,
          body
        )
        response(data, status, headers)
      end
    end

    def release_project_lock(authorization:, key:, token:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.locks.release_project_lock_with_http_info(
          key,
          token,
          SecureRandom.uuid
        )
        response(data, status, headers)
      end
    end

    private

    def build_apis(authorization)
      uri = URI(@api_url)
      configuration = Generated::Configuration.new
      configuration.scheme = uri.scheme
      configuration.host = uri.host
      configuration.host = "#{uri.host}:#{uri.port}" if uri.port != uri.default_port
      configuration.base_path = uri.path == '/' ? '' : uri.path
      configuration.ignore_operation_servers = true
      configuration.access_token = authorization
      configuration.timeout = @timeout
      api_client = ApiClient.new(configuration)
      GeneratedApis.new(
        authentication: Generated::AuthenticationApi.new(api_client),
        database: Generated::DatabaseQueriesApi.new(api_client),
        storage: Generated::StorageObjectsApi.new(api_client),
        locks: Generated::LocksApi.new(api_client)
      )
    end

    def invoke
      yield
    rescue Generated::ApiError => e
      status = e.code.to_i
      raise Error::TransportError.new(e.message), cause: e if status.zero?

      Transport::Response.new(
        status: status,
        body: parse_body(e.response_body),
        headers: e.response_headers || {},
        data: nil
      )
    end

    def response(data, status, headers, binary: nil)
      Transport::Response.new(
        status: status,
        body: plain_value(data),
        headers: headers || {},
        data: binary
      )
    end

    def parse_body(value)
      return {} if value.nil? || value.empty?

      JSON.parse(value)
    rescue JSON::ParserError
      {}
    end

    def plain_value(value)
      value = value.to_hash if value.respond_to?(:to_hash)
      case value
      when Hash
        value.to_h { |key, item| [key.to_s, plain_value(item)] }
      when Array
        value.map { |item| plain_value(item) }
      else
        value
      end
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.to_h { |key, item| [key.to_sym, deep_symbolize(item)] }
      when Array
        value.map { |item| deep_symbolize(item) }
      else
        value
      end
    end

    def binary_data(value)
      if value.respond_to?(:read)
        value.open if value.respond_to?(:closed?) && value.closed? && value.respond_to?(:open)
        value.binmode if value.respond_to?(:binmode)
        value.rewind if value.respond_to?(:rewind)
        value.read.b
      else
        value.to_s.b
      end
    ensure
      value.close! if value.respond_to?(:close!)
    end
  end
end
