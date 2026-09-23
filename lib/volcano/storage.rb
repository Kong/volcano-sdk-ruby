# frozen_string_literal: true

require 'time'

module Volcano
  # Entry point for project object storage.
  class Storage
    def initialize(client, transport, api_url:, anon_key:)
      @client = client.is_a?(StorageSessionAdapter) ? client : StorageSessionAdapter.new(client)
      @transport = transport.is_a?(StorageTransportAdapter) ? transport : StorageTransportAdapter.new(transport)
      @api_url = api_url
      @anon_key = anon_key
    end

    def from(bucket)
      StorageBucket.new(
        @client,
        @transport,
        bucket,
        api_url: @api_url,
        anon_key: @anon_key
      )
    end
  end

  # Operates on objects in one storage bucket.
  class StorageBucket
    include StorageObjectResponse

    def initialize(client, transport, name, api_url:, anon_key:)
      @client = client.is_a?(StorageSessionAdapter) ? client : StorageSessionAdapter.new(client)
      @transport = transport.is_a?(StorageTransportAdapter) ? transport : StorageTransportAdapter.new(transport)
      @name = name.dup.freeze
      @api_url = api_url.dup.freeze
      @anon_key = anon_key.dup.freeze
      freeze
    end

    def upload(path, value, content_type: nil)
      mime_type = upload_content_type(content_type)
      path = storage_paths(path).fetch(0)
      binding = @client.capture_session_binding
      @client.session_token
      content = upload_bytes(value).freeze
      response = storage_request(binding: binding) do |token|
        @transport.upload_storage_object(
          authorization: token,
          bucket_name: @name,
          path: path,
          data: content,
          content_type: mime_type
        )
      end
      storage_payload(Transport.body(response, 201))
    end

    def download(path, range: nil)
      path = storage_paths(path).fetch(0)
      range = range&.dup&.freeze
      response = storage_request do |token|
        @transport.download_storage_object(
          authorization: token,
          bucket_name: @name,
          path: path,
          byte_range: range
        )
      end
      expected_status = range && response.status == 206 ? 206 : 200
      Transport.body(response, expected_status)
      storage_string(response.data).b
    end

    def list(prefix = '', limit: nil, cursor: nil)
      prefix = prefix.dup.freeze
      cursor = cursor&.dup&.freeze
      response = storage_request do |token|
        @transport.list_storage_objects(
          authorization: token,
          bucket_name: @name,
          prefix: prefix,
          limit: limit,
          cursor: cursor
        )
      end
      payload = storage_payload(Transport.body(response, 200))
      StoragePage.new(
        objects: storage_object_list(payload.fetch('objects', [])),
        next_cursor: storage_cursor(payload['next_cursor'])
      )
    end

    private

    def storage_request(binding: @client.capture_session_binding)
      @client.session_request(binding: binding) { |token| Transport.invoke { yield(token) } }
    end

    def upload_content_type(value)
      return if value.nil?
      return value.dup.freeze if value.is_a?(String) && value.match?(/\A[\x20-\x7e]+\z/) && !value.strip.empty?

      raise ArgumentError, 'content_type must be a non-blank printable ASCII string'
    end

    def upload_bytes(value)
      raise ArgumentError, 'upload data must be a String or IO' unless value.is_a?(String) || value.respond_to?(:read)

      bytes = value.is_a?(String) ? value : value.read
      raise ArgumentError, 'upload data must be a String or IO' unless bytes.is_a?(String)

      bytes.b
    end
  end
end
