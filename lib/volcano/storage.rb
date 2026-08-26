# frozen_string_literal: true

module Volcano
  class Storage
    def initialize(client)
      @client = client
    end

    def from(bucket)
      StorageBucket.new(@client, bucket)
    end
  end

  class StorageBucket
    def initialize(client, name)
      @client = client
      @name = name
      freeze
    end

    def upload(path, value)
      bytes = value.respond_to?(:read) ? value.read : value
      raise ArgumentError, 'upload data must be a String or IO' unless bytes.is_a?(String)

      response = Transport.invoke do
        @client.transport.upload_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          path: path,
          data: bytes.b
        )
      end
      Transport.body(response, 201)
    end

    def download(path)
      response = Transport.invoke do
        @client.transport.download_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          path: path
        )
      end
      Transport.body(response, 200)
      response.data.b
    end
  end
end
