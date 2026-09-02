# frozen_string_literal: true

require 'stringio'
require 'tempfile'

module Volcano
  # High-level resumable upload orchestration for one storage bucket.
  class StorageBucket
    SPOOL_READ_SIZE = 1_048_576
    private_constant :SPOOL_READ_SIZE

    def upload_resumable(
      path,
      value,
      content_type: 'application/octet-stream',
      part_size: nil
    )
      with_resumable_upload_source(value) do |source, total_size|
        session = create_upload_session(
          path, total_size: total_size, content_type: content_type, part_size: part_size
        )
        upload_session_parts(path, source, session)
        complete_upload_session(path, session_id: session.session_id)
      end
    end

    private

    def upload_session_parts(path, source, session)
      session.total_parts.times do |part_index|
        upload_part(
          path,
          session_id: session.session_id,
          part_number: part_index + 1,
          data: source.read(session.part_size)
        )
      end
    rescue StandardError
      abort_failed_upload(path, session.session_id)
      raise
    end

    def abort_failed_upload(path, session_id)
      abort_upload_session(path, session_id: session_id)
    rescue Error::VolcanoError
      nil
    end

    def with_resumable_upload_source(value, &)
      return yield StringIO.new(value.b), value.bytesize if value.is_a?(String)
      raise ArgumentError, 'upload data must be a String or IO' unless value.respond_to?(:read)

      remaining = remaining_upload_bytes(value)
      return yield value, remaining unless remaining.nil?

      with_spooled_upload_source(value, &)
    end

    def remaining_upload_bytes(source)
      return unless source.respond_to?(:size) && source.respond_to?(:pos)

      source.size - source.pos
    rescue IOError, SystemCallError
      nil
    end

    def with_spooled_upload_source(source)
      Tempfile.create('volcano-upload') do |file|
        file.binmode
        spool_upload_source(source, file)
        file.rewind
        yield file, file.size
      end
    end

    def spool_upload_source(source, file)
      loop do
        chunk = source.read(SPOOL_READ_SIZE)
        break if chunk.nil?

        file.write(chunk)
      end
    end
  end
end
