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

# Public namespace for the Volcano Ruby SDK.
module Volcano
  private_constant :Generated
  require_relative 'generated_transport_support'
  require_relative 'generated_transport_auth'
  require_relative 'generated_transport_anonymous'
  require_relative 'generated_transport_confirmation'
  require_relative 'generated_transport_email_change'
  require_relative 'generated_transport_sessions'
  require_relative 'generated_transport_oauth'

  # Adapts the generated OpenAPI client to the stable SDK transport contract.
  class GeneratedTransport
    include ApiFactory
    include ValueNormalization

    GeneratedApis = Data.define(:authentication, :oauth, :database, :storage, :locks)

    def initialize(api_url:, timeout: 60, api_factory: nil)
      @api_url = api_url
      @timeout = timeout
      @api_factory = api_factory || method(:build_apis)
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

    def query_database_insert(authorization:, database_name:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::DatabaseInsertRequest.new(deep_symbolize(body))
        data, status, headers = apis.database.query_database_insert_with_http_info(
          database_name,
          request
        )
        response(data, status, headers)
      end
    end

    def upload_storage_object(authorization:, bucket_name:, path:, data:)
      invoke do
        apis = @api_factory.call(authorization)
        with_upload_file(path, data) do |file|
          result = apis.storage.upload_storage_object_with_http_info(bucket_name, path, file)
          data_value, status, headers = result
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
        result = apis.locks.acquire_project_lock_with_http_info(key, token, SecureRandom.uuid, body)
        data, status, headers = result
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

    def with_upload_file(path, data)
      Tempfile.create(['volcano-sdk-upload', File.extname(path)], binmode: true) do |file|
        file.write(data)
        file.flush
        yield file
      end
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
  end
end
