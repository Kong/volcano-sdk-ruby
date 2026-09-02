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
end
