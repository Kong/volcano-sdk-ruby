# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeStorageTransport
      def upload_storage_object(**arguments)
        @calls << [:upload_storage_object, arguments]
        Volcano::Transport::Response.new(status: 201, body: { 'name' => 'a.txt', 'size' => 5 }, headers: {}, data: nil)
      end

      def download_storage_object(**arguments)
        @calls << [:download_storage_object, arguments]
        status = arguments[:byte_range] ? @range_download_status : 200
        Volcano::Transport::Response.new(status: status, body: nil, headers: {}, data: "hello\x00".b)
      end

      def list_storage_objects(**arguments)
        @calls << [:list_storage_objects, arguments]
        Volcano::Transport::Response.new(status: 200, body: storage_page_body, headers: {}, data: nil)
      end

      def delete_storage_object(**arguments)
        @calls << [:delete_storage_object, arguments]
        Volcano::Transport::Response.new(status: 200, body: nil, headers: {}, data: nil)
      end

      def move_storage_object(**arguments)
        @calls << [:move_storage_object, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'id' => '00000000-0000-4000-8000-000000000020',
            'bucket_id' => '00000000-0000-4000-8000-000000000030',
            'name' => arguments.fetch(:to_path),
            'size' => 5,
            'mime_type' => 'text/plain',
            'is_public' => false
          },
          headers: {},
          data: nil
        )
      end

      def copy_storage_object(**arguments)
        @calls << [:copy_storage_object, arguments]
        Volcano::Transport::Response.new(
          status: 201,
          body: {
            'id' => '00000000-0000-4000-8000-000000000021',
            'bucket_id' => '00000000-0000-4000-8000-000000000030',
            'name' => arguments.fetch(:to_path),
            'size' => 5,
            'mime_type' => 'text/plain',
            'is_public' => false
          },
          headers: {},
          data: nil
        )
      end

      def update_storage_object_visibility(**arguments)
        @calls << [:update_storage_object_visibility, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'id' => '00000000-0000-4000-8000-000000000020',
            'bucket_id' => '00000000-0000-4000-8000-000000000030',
            'name' => arguments.fetch(:path),
            'size' => 5,
            'mime_type' => 'image/png',
            'is_public' => arguments.fetch(:is_public),
            'public_url' => if arguments.fetch(:is_public)
                              'https://api.test.volcano.dev/public/project/assets/avatars/a.png'
                            end
          },
          headers: {},
          data: nil
        )
      end

      private

      def storage_page_body
        {
          'objects' => [
            {
              'id' => '00000000-0000-4000-8000-000000000020',
              'bucket_id' => '00000000-0000-4000-8000-000000000030',
              'name' => 'avatars/a.png',
              'size' => 5,
              'mime_type' => 'image/png',
              'is_public' => false,
              'owner_id' => '00000000-0000-4000-8000-000000000010',
              'etag' => 'etag-1',
              'metadata' => { 'width' => 32, 'labels' => ['profile'] },
              'created_at' => '2026-08-26T12:00:00Z',
              'updated_at' => '2026-08-26T12:01:00Z'
            }
          ],
          'next_cursor' => 'cursor-2'
        }
      end
    end

    # Implements resumable storage session creation for the facade test transport.
  end
end
