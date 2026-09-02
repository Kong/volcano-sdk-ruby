# frozen_string_literal: true

require 'time'

module Volcano
  # Entry point for project object storage.
  class Storage
    def initialize(client, transport, api_url:, anon_key:)
      @client = client
      @transport = transport
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
    def initialize(client, transport, name, api_url:, anon_key:)
      @client = client
      @transport = transport
      @name = name
      @api_url = api_url.dup.freeze
      @anon_key = anon_key.dup.freeze
      freeze
    end

    def upload(path, value)
      response = Transport.invoke do
        @transport.upload_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          path: path,
          data: upload_bytes(value)
        )
      end
      Transport.body(response, 201)
    end

    def download(path)
      response = Transport.invoke do
        @transport.download_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          path: path
        )
      end
      Transport.body(response, 200)
      response.data.b
    end

    def list(prefix = '', limit: nil, cursor: nil)
      response = Transport.invoke do
        @transport.list_storage_objects(
          authorization: @client.session_token,
          bucket_name: @name,
          prefix: prefix,
          limit: limit,
          cursor: cursor
        )
      end
      payload = Transport.body(response, 200)
      next_cursor = payload['next_cursor']
      StoragePage.new(
        objects: payload.fetch('objects', []).map { |object| storage_object(object) },
        next_cursor: next_cursor == '' ? nil : next_cursor
      )
    end

    private

    def upload_bytes(value)
      bytes = value.respond_to?(:read) ? value.read : value
      raise ArgumentError, 'upload data must be a String or IO' unless bytes.is_a?(String)

      bytes.b
    end

    def storage_object(payload)
      StorageObject.new(
        id: payload.fetch('id'),
        bucket_id: payload.fetch('bucket_id'),
        name: payload.fetch('name'),
        size: payload.fetch('size'),
        mime_type: payload.fetch('mime_type'),
        is_public: payload.fetch('is_public'),
        owner_id: payload['owner_id'],
        etag: payload['etag'],
        metadata: payload['metadata'],
        created_at: parse_time(payload['created_at']),
        updated_at: parse_time(payload['updated_at']),
        public_url: payload['public_url']
      )
    end

    def parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end
  end
end
