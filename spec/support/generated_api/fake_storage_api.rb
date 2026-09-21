# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
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

      def download_storage_object_with_http_info(bucket, path, options = {})
        @calls << [:download, bucket, path, options]
        ["hello\x00".b, 200, { 'content-type' => 'application/octet-stream' }]
      end

      def create_upload_session_with_http_info(bucket, path, request)
        @calls << [:create_session, bucket, path, request]
        session = FakeGeneratedModel.new(
          session_id: 'session-123', part_size: 8_388_608, total_parts: 3,
          expires_at: Time.iso8601('2026-09-09T12:00:00Z')
        )
        [session, 201, {}]
      end

      def upload_part_with_http_info(bucket, path, session_id, part_number, data)
        @calls << [:upload_part, bucket, path, session_id, part_number, data]
        [FakeGeneratedModel.new(part_number: part_number, etag: 'etag-part', size: data.bytesize), 200, {}]
      end

      def complete_upload_session_with_http_info(bucket, path, session_id)
        @calls << [:complete_upload_session, bucket, path, session_id]
        object = FakeGeneratedModel.new(
          id: 'object-123', bucket_id: 'bucket-123', name: path, size: 20_000_000,
          mime_type: 'video/mp4', is_public: false
        )
        [FakeGeneratedModel.new(object: object), 200, {}]
      end

      def get_upload_session_with_http_info(bucket, path, session_id)
        @calls << [:get_upload_session, bucket, path, session_id]
        status = FakeGeneratedModel.new(
          session_id: session_id, status: 'uploading', path: path, content_type: 'video/mp4',
          total_size: 20_000_000, part_size: 8_388_608, total_parts: 3,
          parts_uploaded: 1, bytes_uploaded: 8_388_608, parts: [],
          expires_at: Time.iso8601('2026-09-09T12:00:00Z'),
          created_at: Time.iso8601('2026-09-02T12:00:00Z')
        )
        [status, 200, {}]
      end

      def abort_upload_session_with_http_info(bucket, path, session_id)
        @calls << [:abort_upload_session, bucket, path, session_id]
        [nil, 200, {}]
      end

      def list_storage_objects_with_http_info(bucket, options)
        @calls << [:list, bucket, options]
        page = FakeGeneratedModel.new(objects: [], next_cursor: 'cursor-2')
        [page, 200, {}]
      end

      def delete_storage_object_with_http_info(bucket, path)
        @calls << [:delete, bucket, path]
        [nil, 200, {}]
      end

      def move_storage_object_with_http_info(bucket, request)
        @calls << [:move, bucket, request]
        [FakeGeneratedModel.new(name: request.to), 200, {}]
      end

      def copy_storage_object_with_http_info(bucket, request)
        @calls << [:copy, bucket, request]
        [FakeGeneratedModel.new(name: request.to), 201, {}]
      end

      def update_storage_object_visibility_with_http_info(bucket, path, request)
        @calls << [:visibility, bucket, path, request]
        [FakeGeneratedModel.new(name: path, is_public: request.is_public), 200, {}]
      end
    end
  end
end
