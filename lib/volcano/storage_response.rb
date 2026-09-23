# frozen_string_literal: true

module Volcano
  # Decodes resumable-upload responses before creating public records.
  module StorageResponse
    private

    def upload_session(payload)
      payload = storage_payload(payload)
      UploadSession.new(
        session_id: storage_string(payload.fetch('session_id')),
        part_size: storage_integer(payload.fetch('part_size')),
        total_parts: storage_integer(payload.fetch('total_parts')),
        expires_at: storage_time(payload.fetch('expires_at'))
      )
    end

    def upload_part_metadata(payload)
      payload = storage_payload(payload)
      UploadPart.new(
        part_number: storage_integer(payload.fetch('part_number')),
        etag: storage_string(payload.fetch('etag')),
        size: storage_integer(payload.fetch('size'))
      )
    end

    def upload_session_status(payload)
      payload = storage_payload(payload)
      text = storage_status_text(payload)
      counts = storage_status_counts(payload)
      storage_status_record(payload, text, counts)
    end

    def storage_status_record(payload, text, counts)
      UploadSessionStatus.new(
        session_id: text.fetch(0), status: text.fetch(1), path: text.fetch(2),
        content_type: text.fetch(3), total_size: counts.fetch(0), part_size: counts.fetch(1),
        total_parts: counts.fetch(2), parts_uploaded: counts.fetch(3),
        bytes_uploaded: counts.fetch(4), parts: storage_parts(payload.fetch('parts', [])),
        expires_at: storage_time(payload.fetch('expires_at')),
        created_at: storage_time(payload.fetch('created_at'))
      )
    end

    def storage_status_text(payload)
      [
        storage_string(payload.fetch('session_id')), storage_string(payload.fetch('status')),
        storage_string(payload.fetch('path')), storage_string(payload.fetch('content_type'))
      ]
    end

    def storage_status_counts(payload)
      [
        storage_integer(payload.fetch('total_size')), storage_integer(payload.fetch('part_size')),
        storage_integer(payload.fetch('total_parts')), storage_integer(payload.fetch('parts_uploaded')),
        storage_integer(payload.fetch('bytes_uploaded'))
      ]
    end

    def storage_parts(value)
      raise Error::TransportError, 'invalid upload parts' unless value.is_a?(Array)

      value.map { |part| upload_part_metadata(part) }
    end

    def storage_payload(value)
      raise Error::TransportError, 'invalid storage response' unless value.is_a?(Hash)

      value
    end

    def storage_string(value)
      raise Error::TransportError, 'invalid storage string' unless value.is_a?(String)

      value
    end

    def storage_integer(value)
      raise Error::TransportError, 'invalid storage integer' unless value.is_a?(Integer)

      value
    end

    def storage_time(value)
      return value if value.is_a?(Time)
      return Time.iso8601(value) if value.is_a?(String)

      raise Error::TransportError, 'invalid storage time'
    end
  end
end
