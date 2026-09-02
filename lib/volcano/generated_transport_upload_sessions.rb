# frozen_string_literal: true

module Volcano
  # Resumable storage operations for the internal generated transport.
  class GeneratedTransport
    def create_upload_session(authorization:, bucket_name:, request:)
      invoke do
        attributes = {
          object_path: request.path,
          content_type: request.content_type,
          total_size: request.total_size,
          part_size: request.part_size
        }.compact
        generated_request = Generated::CreateUploadSessionRequest.new(attributes)
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.create_upload_session_with_http_info(
          bucket_name, request.path, generated_request
        )
        response(data, status, headers)
      end
    end

    def upload_part(authorization:, bucket_name:, request:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.upload_part_with_http_info(
          bucket_name,
          request.path,
          request.session_id,
          request.part_number,
          request.data
        )
        response(data, status, headers)
      end
    end

    def complete_upload_session(authorization:, bucket_name:, request:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.complete_upload_session_with_http_info(
          bucket_name, request.path, request.session_id
        )
        response(data, status, headers)
      end
    end
  end
end
