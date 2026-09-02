# frozen_string_literal: true

module Volcano
  # Internal transport implementation assembled across support modules.
  class GeneratedTransport
    # Resolves generated model constants across the private namespace boundary.
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

    # Corrects generated content negotiation and private model lookup.
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

    # Captures a generated request URL without performing network I/O.
    class AuthorizationURLApiClient < ApiClient
      def call_api(http_method, path, options = {})
        [build_request(http_method, path, options).url, 0, {}]
      end
    end
    private_constant :AuthorizationURLApiClient

    # Implements storage endpoints omitted by the generated API surface.
    class StorageApi < Generated::StorageObjectsApi
      UPLOAD_OPTIONS = {
        operation: :'StorageObjectsApi.upload_storage_object',
        header_params: { 'Accept' => 'application/json', 'Content-Type' => 'multipart/form-data' }.freeze,
        auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
        return_type: 'StorageObject'
      }.freeze
      DOWNLOAD_OPTIONS = {
        operation: :'StorageObjectsApi.download_storage_object',
        header_params: { 'Accept' => 'application/octet-stream, application/json' }.freeze,
        auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
        return_type: 'File'
      }.freeze
      DELETE_OPTIONS = {
        operation: :'StorageObjectsApi.delete_storage_object',
        header_params: { 'Accept' => 'application/json' }.freeze,
        auth_names: %w[ServiceRoleKey AuthUserAccessToken].freeze
      }.freeze

      def upload_storage_object_with_http_info(bucket_name, path, file, opts = {})
        options = opts.merge(UPLOAD_OPTIONS).merge(form_params: { 'file' => file })
        call_storage_api(:POST, bucket_name, path, options)
      end

      def download_storage_object_with_http_info(bucket_name, path, opts = {})
        call_storage_api(:GET, bucket_name, path, opts.merge(DOWNLOAD_OPTIONS))
      end

      def delete_storage_object_with_http_info(bucket_name, path, opts = {})
        call_storage_api(:DELETE, bucket_name, path, opts.merge(DELETE_OPTIONS))
      end

      private

      def call_storage_api(method, bucket_name, path, options)
        raise ArgumentError, 'bucket_name is required' if bucket_name.nil?
        raise ArgumentError, 'path is required' if path.nil?

        bucket = CGI.escapeURIComponent(bucket_name.to_s)
        object_path = CGI.escapeURIComponent(path.to_s).gsub('%2F', '/')
        api_client.call_api(method, "/storage/#{bucket}/#{object_path}", options)
      end
    end

    # Normalizes values returned by the generated client.
    module ValueNormalization
      private

      def parse_body(value)
        return {} if value.nil? || value.empty?

        JSON.parse(value)
      rescue JSON::ParserError
        {}
      end

      def plain_value(value)
        value = value.to_hash if value.respond_to?(:to_hash)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, plain_value(item)] }
        when Array then value.map { |item| plain_value(item) }
        else value
        end
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_sym, deep_symbolize(item)] }
        when Array then value.map { |item| deep_symbolize(item) }
        else value
        end
      end

      def binary_data(value)
        return value.to_s.b unless value.respond_to?(:read)

        prepare_stream(value)
        value.read.b
      ensure
        value.close! if value.respond_to?(:close!)
      end

      def prepare_stream(value)
        value.open if value.respond_to?(:closed?) && value.closed? && value.respond_to?(:open)
        value.binmode if value.respond_to?(:binmode)
        value.rewind if value.respond_to?(:rewind)
      end
    end

    # Builds generated API wrappers with consistent authentication and timeouts.
    module ApiFactory
      private

      def build_apis(authorization)
        api_client = ApiClient.new(generated_configuration(authorization))
        generated_apis(api_client)
      end

      def generated_configuration(authorization)
        uri = URI(@api_url)
        Generated::Configuration.new.tap do |configuration|
          configuration.scheme = uri.scheme
          configuration.host = host_with_port(uri)
          configuration.base_path = uri.path == '/' ? '' : uri.path
          configuration.ignore_operation_servers = true
          configuration.access_token = authorization
          configuration.timeout = timeout_milliseconds
        end
      end

      def timeout_milliseconds
        (@timeout * 1_000).round
      end

      def generated_apis(api_client)
        GeneratedApis.new(
          authentication: Generated::AuthenticationApi.new(api_client),
          oauth: Generated::OAuthAuthenticationApi.new(api_client),
          database: Generated::DatabaseQueriesApi.new(api_client),
          storage: StorageApi.new(api_client),
          locks: Generated::LocksApi.new(api_client)
        )
      end

      def oauth_authorization_api
        api_client = AuthorizationURLApiClient.new(generated_configuration(nil))
        Generated::OAuthAuthenticationApi.new(api_client)
      end

      def host_with_port(uri)
        return uri.host if uri.port == uri.default_port

        "#{uri.host}:#{uri.port}"
      end
    end
  end
end
