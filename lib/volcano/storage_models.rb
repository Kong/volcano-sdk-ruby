# frozen_string_literal: true

module Volcano
  STORAGE_OBJECT_ATTRIBUTES = %i[
    id bucket_id name size mime_type is_public owner_id etag metadata created_at updated_at public_url
  ].freeze
  private_constant :STORAGE_OBJECT_ATTRIBUTES

  StorageObject = Data.define(*STORAGE_OBJECT_ATTRIBUTES) do
    def initialize(**attributes)
      unknown = attributes.keys - STORAGE_OBJECT_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = STORAGE_OBJECT_ATTRIBUTES.first(6) - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = STORAGE_OBJECT_ATTRIBUTES.to_h do |name|
        [name, immutable_value(attributes[name])]
      end
      super(**values)
    end

    private

    def immutable_value(value)
      case value
      when Hash
        value.to_h { |key, item| [immutable_value(key), immutable_value(item)] }.freeze
      when Array then value.map { |item| immutable_value(item) }.freeze
      when String then value.dup.freeze
      else value.frozen? ? value : value.dup.freeze
      end
    end
  end

  StoragePage = Data.define(:objects, :next_cursor) do
    def initialize(objects:, next_cursor: nil)
      cursor = next_cursor.nil? ? nil : next_cursor.dup.freeze
      super(objects: objects.to_a.dup.freeze, next_cursor: cursor)
    end
  end

  UploadSessionRequest = Data.define(:path, :content_type, :total_size, :part_size) do
    def initialize(path:, content_type:, total_size:, part_size: nil)
      super(
        path: path.dup.freeze,
        content_type: content_type.dup.freeze,
        total_size: total_size,
        part_size: part_size
      )
    end
  end
  private_constant :UploadSessionRequest

  UploadPartRequest = Data.define(:path, :session_id, :part_number, :data) do
    def initialize(path:, session_id:, part_number:, data:)
      super(
        path: path.dup.freeze,
        session_id: session_id.dup.freeze,
        part_number: part_number,
        data: data.dup.freeze
      )
    end
  end
  private_constant :UploadPartRequest

  UploadSession = Data.define(:session_id, :part_size, :total_parts, :expires_at) do
    def initialize(session_id:, part_size:, total_parts:, expires_at:)
      super(
        session_id: session_id.dup.freeze,
        part_size: part_size,
        total_parts: total_parts,
        expires_at: expires_at.dup.freeze
      )
    end
  end

  UploadPart = Data.define(:part_number, :etag, :size) do
    def initialize(part_number:, etag:, size:)
      super(part_number: part_number, etag: etag.dup.freeze, size: size)
    end
  end
end
