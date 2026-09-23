# frozen_string_literal: true

module Volcano
  # Resumable upload operations for one storage bucket.
  class StorageBucket
    include StorageResponse

    def create_upload_session(
      path,
      total_size:,
      content_type: 'application/octet-stream',
      part_size: nil
    )
      request = UploadSessionRequest.new(
        path: path,
        content_type: content_type,
        total_size: total_size,
        part_size: part_size
      )
      response = storage_request do |token|
        @transport.create_upload_session(
          authorization: token,
          bucket_name: @name,
          request: request
        )
      end
      upload_session(Transport.body(response, 201))
    end

    def upload_part(path, session_id:, part_number:, data:)
      request = UploadPartRequest.new(
        path: path,
        session_id: session_id,
        part_number: part_number,
        data: upload_bytes(data)
      )
      response = storage_request do |token|
        @transport.upload_part(
          authorization: token,
          bucket_name: @name,
          request: request
        )
      end
      upload_part_metadata(Transport.body(response, 200))
    end

    def complete_upload_session(path, session_id:)
      request = UploadSessionReference.new(path: path, session_id: session_id)
      response = storage_request do |token|
        @transport.complete_upload_session(
          authorization: token,
          bucket_name: @name,
          request: request
        )
      end
      storage_object(storage_payload(Transport.body(response, 200)).fetch('object'))
    end

    def get_upload_session(path, session_id:)
      request = UploadSessionReference.new(path: path, session_id: session_id)
      response = storage_request do |token|
        @transport.get_upload_session(
          authorization: token,
          bucket_name: @name,
          request: request
        )
      end
      upload_session_status(Transport.body(response, 200))
    end

    def abort_upload_session(path, session_id:)
      request = UploadSessionReference.new(path: path, session_id: session_id)
      response = storage_request do |token|
        @transport.abort_upload_session(
          authorization: token,
          bucket_name: @name,
          request: request
        )
      end
      Transport.body(response, 200)
      nil
    end
  end
end
