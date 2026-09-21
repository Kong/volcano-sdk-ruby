# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeUploadSessionTransport
      attr_accessor :fail_abort_upload, :fail_upload_part_number,
                    :upload_session_part_size, :upload_session_total_parts

      def create_upload_session(**arguments)
        @calls << [:create_upload_session, arguments]
        body = {
          'session_id' => 'session-123',
          'part_size' => upload_session_part_size || 8_388_608,
          'total_parts' => upload_session_total_parts || 3,
          'expires_at' => '2026-09-09T12:00:00Z'
        }
        Volcano::Transport::Response.new(status: 201, body: body, headers: {}, data: nil)
      end

      def upload_part(**arguments)
        @calls << [:upload_part, arguments]
        request = arguments.fetch(:request)
        if request.part_number == fail_upload_part_number
          return Volcano::Transport::Response.new(
            status: 500, body: { 'error' => 'part upload failed' }, headers: {}, data: nil
          )
        end
        body = {
          'part_number' => request.part_number,
          'etag' => 'etag-part-1',
          'size' => request.data.bytesize
        }
        Volcano::Transport::Response.new(status: 200, body: body, headers: {}, data: nil)
      end

      def complete_upload_session(**arguments)
        @calls << [:complete_upload_session, arguments]
        request = arguments.fetch(:request)
        object = {
          'id' => '00000000-0000-4000-8000-000000000020',
          'bucket_id' => '00000000-0000-4000-8000-000000000030',
          'name' => request.path,
          'size' => 20_000_000,
          'mime_type' => 'video/mp4',
          'is_public' => false,
          'etag' => 'etag-complete'
        }
        Volcano::Transport::Response.new(status: 200, body: { 'object' => object }, headers: {}, data: nil)
      end

      def get_upload_session(**arguments)
        @calls << [:get_upload_session, arguments]
        request = arguments.fetch(:request)
        body = {
          'session_id' => request.session_id,
          'status' => 'uploading',
          'path' => request.path,
          'content_type' => 'video/mp4',
          'total_size' => 20_000_000,
          'part_size' => 8_388_608,
          'total_parts' => 3,
          'parts_uploaded' => 1,
          'bytes_uploaded' => 8_388_608,
          'parts' => [{ 'part_number' => 1, 'etag' => 'etag-part-1', 'size' => 8_388_608 }],
          'expires_at' => '2026-09-09T12:00:00Z',
          'created_at' => '2026-09-02T12:00:00Z'
        }
        Volcano::Transport::Response.new(status: 200, body: body, headers: {}, data: nil)
      end

      def abort_upload_session(**arguments)
        @calls << [:abort_upload_session, arguments]
        return failed_abort_response if fail_abort_upload

        Volcano::Transport::Response.new(
          status: 200, body: { 'message' => 'upload session aborted' }, headers: {}, data: nil
        )
      end

      private

      def failed_abort_response
        Volcano::Transport::Response.new(status: 500, body: { 'error' => 'abort failed' }, headers: {}, data: nil)
      end
    end
  end
end
