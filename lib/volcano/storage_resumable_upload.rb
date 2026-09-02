# frozen_string_literal: true

module Volcano
  # High-level resumable upload orchestration for one storage bucket.
  class StorageBucket
    def upload_resumable(
      path,
      value,
      content_type: 'application/octet-stream',
      part_size: nil
    )
      data = upload_bytes(value)
      session = create_upload_session(
        path, total_size: data.bytesize, content_type: content_type, part_size: part_size
      )
      upload_session_parts(path, data, session)
      complete_upload_session(path, session_id: session.session_id)
    end

    private

    def upload_session_parts(path, data, session)
      session.total_parts.times do |part_index|
        upload_part(
          path,
          session_id: session.session_id,
          part_number: part_index + 1,
          data: data.byteslice(part_index * session.part_size, session.part_size)
        )
      end
    rescue Error::VolcanoError
      abort_failed_upload(path, session.session_id)
      raise
    end

    def abort_failed_upload(path, session_id)
      abort_upload_session(path, session_id: session_id)
    rescue Error::VolcanoError
      nil
    end
  end
end
