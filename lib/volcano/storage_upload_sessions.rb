# frozen_string_literal: true

module Volcano
  # Resumable upload operations for one storage bucket.
  class StorageBucket
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
      response = Transport.invoke do
        @transport.create_upload_session(
          authorization: @client.session_token,
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
      response = Transport.invoke do
        @transport.upload_part(
          authorization: @client.session_token,
          bucket_name: @name,
          request: request
        )
      end
      upload_part_metadata(Transport.body(response, 200))
    end

    def complete_upload_session(path, session_id:)
      request = UploadSessionReference.new(path: path, session_id: session_id)
      response = Transport.invoke do
        @transport.complete_upload_session(
          authorization: @client.session_token,
          bucket_name: @name,
          request: request
        )
      end
      storage_object(Transport.body(response, 200).fetch('object'))
    end

    def get_upload_session(path, session_id:)
      request = UploadSessionReference.new(path: path, session_id: session_id)
      response = Transport.invoke do
        @transport.get_upload_session(
          authorization: @client.session_token,
          bucket_name: @name,
          request: request
        )
      end
      upload_session_status(Transport.body(response, 200))
    end

    private

    def upload_session(payload)
      UploadSession.new(
        session_id: payload.fetch('session_id'),
        part_size: payload.fetch('part_size'),
        total_parts: payload.fetch('total_parts'),
        expires_at: parse_time(payload.fetch('expires_at'))
      )
    end

    def upload_part_metadata(payload)
      UploadPart.new(
        part_number: payload.fetch('part_number'),
        etag: payload.fetch('etag'),
        size: payload.fetch('size')
      )
    end

    def upload_session_status(payload)
      attributes = UPLOAD_SESSION_STATUS_ATTRIBUTES.to_h do |name|
        [name, payload.fetch(name.to_s)]
      end
      attributes[:parts] = attributes.fetch(:parts).map { |part| upload_part_metadata(part) }
      attributes[:expires_at] = parse_time(attributes.fetch(:expires_at))
      attributes[:created_at] = parse_time(attributes.fetch(:created_at))
      UploadSessionStatus.new(**attributes)
    end
  end
end
