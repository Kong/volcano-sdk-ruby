# frozen_string_literal: true

module Volcano
  UploadSessionRequest = Data.define(:path, :content_type, :total_size, :part_size)

  # Freezes the arguments sent to create a resumable upload.
  class UploadSessionRequest
    # @dynamic path, content_type, total_size, part_size
    def initialize(path:, content_type:, total_size:, part_size: nil)
      path = path.dup.freeze
      content_type = content_type.dup.freeze
      super
    end
  end
  private_constant :UploadSessionRequest

  UploadPartRequest = Data.define(:path, :session_id, :part_number, :data)

  # Freezes one resumable upload part before transport dispatch.
  class UploadPartRequest
    # @dynamic path, session_id, part_number, data
    def initialize(path:, session_id:, part_number:, data:)
      path = path.dup.freeze
      session_id = session_id.dup.freeze
      data = data.dup.freeze
      super
    end
  end
  private_constant :UploadPartRequest

  UploadSessionReference = Data.define(:path, :session_id)

  # Freezes the path and identifier used for upload session operations.
  class UploadSessionReference
    # @dynamic path, session_id
    def initialize(path:, session_id:)
      path = path.dup.freeze
      session_id = session_id.dup.freeze
      super
    end
  end
  private_constant :UploadSessionReference

  UploadSession = Data.define(:session_id, :part_size, :total_parts, :expires_at)

  # Describes a newly created upload session.
  class UploadSession
    # @dynamic session_id, part_size, total_parts, expires_at, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(session_id:, part_size:, total_parts:, expires_at:)
      session_id = session_id.dup.freeze
      expires_at = expires_at.dup.freeze
      super
    end
  end

  UploadPart = Data.define(:part_number, :etag, :size)

  # Describes an accepted upload part.
  class UploadPart
    # @dynamic part_number, etag, size, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(part_number:, etag:, size:)
      etag = etag.dup.freeze
      super
    end
  end

  UPLOAD_SESSION_STATUS_ATTRIBUTES = %i[
    session_id status path content_type total_size part_size total_parts parts_uploaded
    bytes_uploaded parts expires_at created_at
  ].freeze
  private_constant :UPLOAD_SESSION_STATUS_ATTRIBUTES

  UploadSessionStatus = Data.define(*UPLOAD_SESSION_STATUS_ATTRIBUTES)

  # Freezes upload progress returned by storage.
  class UploadSessionStatus
    def initialize(**attributes)
      unknown = attributes.keys - UPLOAD_SESSION_STATUS_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = UPLOAD_SESSION_STATUS_ATTRIBUTES - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = UPLOAD_SESSION_STATUS_ATTRIBUTES.to_h do |name|
        [name, immutable_value(attributes.fetch(name))]
      end
      attributes = values
      super
    end

    private

    def immutable_value(value)
      case value
      when Array then value.to_a.dup.freeze
      when String then value.dup.freeze
      else value.frozen? ? value : value.dup.freeze
      end
    end
  end
end
