# frozen_string_literal: true

module Volcano
  # Narrows generated and test transport calls to checked storage responses.
  class StorageTransportAdapter
    def initialize(transport)
      @transport = transport
    end

    def upload_storage_object(authorization:, bucket_name:, path:, data:, content_type:)
      invoke(:upload_storage_object, authorization: authorization, bucket_name: bucket_name,
                                     path: path, data: data, content_type: content_type)
    end

    def download_storage_object(authorization:, bucket_name:, path:, byte_range:)
      invoke(:download_storage_object, authorization: authorization, bucket_name: bucket_name,
                                       path: path, byte_range: byte_range)
    end

    def list_storage_objects(authorization:, bucket_name:, prefix:, limit:, cursor:)
      invoke(:list_storage_objects, authorization: authorization, bucket_name: bucket_name,
                                    prefix: prefix, limit: limit, cursor: cursor)
    end

    def delete_storage_object(authorization:, bucket_name:, path:)
      invoke(:delete_storage_object, authorization: authorization, bucket_name: bucket_name, path: path)
    end

    def move_storage_object(authorization:, bucket_name:, from_path:, to_path:)
      invoke(:move_storage_object, authorization: authorization, bucket_name: bucket_name,
                                   from_path: from_path, to_path: to_path)
    end

    def copy_storage_object(authorization:, bucket_name:, from_path:, to_path:)
      invoke(:copy_storage_object, authorization: authorization, bucket_name: bucket_name,
                                   from_path: from_path, to_path: to_path)
    end

    def update_storage_object_visibility(authorization:, bucket_name:, path:, is_public:)
      invoke(:update_storage_object_visibility, authorization: authorization, bucket_name: bucket_name,
                                                path: path, is_public: is_public)
    end

    def create_upload_session(authorization:, bucket_name:, request:)
      invoke(:create_upload_session, authorization: authorization, bucket_name: bucket_name, request: request)
    end

    def upload_part(authorization:, bucket_name:, request:)
      invoke(:upload_part, authorization: authorization, bucket_name: bucket_name, request: request)
    end

    def complete_upload_session(authorization:, bucket_name:, request:)
      invoke(:complete_upload_session, authorization: authorization, bucket_name: bucket_name, request: request)
    end

    def get_upload_session(authorization:, bucket_name:, request:)
      invoke(:get_upload_session, authorization: authorization, bucket_name: bucket_name, request: request)
    end

    def abort_upload_session(authorization:, bucket_name:, request:)
      invoke(:abort_upload_session, authorization: authorization, bucket_name: bucket_name, request: request)
    end

    private

    def invoke(name, **arguments)
      response = @transport.public_send(name, **arguments)
      raise Error::TransportError, 'invalid storage transport response' unless response.is_a?(Transport::Response)

      response
    end
  end
end
