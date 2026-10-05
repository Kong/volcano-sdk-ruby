# frozen_string_literal: true

require 'json'

module Volcano
  # Validates object metadata and paginated storage responses.
  module StorageObjectResponse
    include StorageResponse

    private

    def storage_object(payload)
      payload = storage_payload(payload)
      required = storage_object_required(payload)
      optional = storage_object_optional(payload)
      StorageObject.new(
        id: required.fetch(0), bucket_id: required.fetch(1), name: required.fetch(2),
        size: required.fetch(3), mime_type: required.fetch(4), is_public: required.fetch(5),
        owner_id: optional.fetch(0), etag: optional.fetch(1), metadata: optional.fetch(2),
        created_at: optional.fetch(3), updated_at: optional.fetch(4), public_url: optional.fetch(5)
      )
    end

    def storage_object_required(payload)
      [
        storage_string(payload.fetch('id')), storage_string(payload.fetch('bucket_id')),
        storage_string(payload.fetch('name')), storage_integer(payload.fetch('size')),
        storage_string(payload.fetch('mime_type')), storage_boolean(payload.fetch('is_public'))
      ]
    end

    def storage_object_optional(payload)
      [
        storage_optional_string(payload['owner_id']), storage_optional_string(payload['etag']),
        storage_optional_metadata(payload['metadata']), storage_optional_time(payload['created_at']),
        storage_optional_time(payload['updated_at']), storage_optional_string(payload['public_url'])
      ]
    end

    def storage_object_list(value)
      raise Error::TransportError, 'invalid storage objects' unless value.is_a?(Array)

      value.map { |object| storage_object(object) }
    end

    def storage_cursor(value)
      return if value.nil? || value == ''

      storage_string(value)
    end

    def storage_boolean(value)
      return true if value == true
      return false if value == false

      raise Error::TransportError, 'invalid storage boolean'
    end

    def storage_optional_string(value)
      value.nil? ? nil : storage_string(value)
    end

    def storage_optional_time(value)
      value.nil? ? nil : storage_time(value)
    end

    def storage_optional_metadata(value)
      value.nil? ? nil : storage_json_hash(value)
    end

    def storage_json_hash(value)
      raise Error::TransportError, 'invalid storage JSON object' unless value.is_a?(Hash)

      # @type var active: Hash[Integer, bool]
      active = {}
      copy = storage_json_container(value, active) { storage_json_entries(value, active) }
      JSON.generate(copy)
      copy
    rescue JSON::GeneratorError
      raise Error::TransportError, 'invalid storage JSON value', cause: nil
    end

    def storage_json_entries(value, active)
      value.to_h do |key, item|
        raise Error::TransportError, 'invalid storage JSON key' unless key.is_a?(String)

        [key, storage_json_value(item, active)]
      end
    end

    def storage_json_value(value, active)
      case value
      when NilClass, TrueClass, FalseClass, Integer, Float, String then value
      when Array then storage_json_container(value, active) { value.map { |item| storage_json_value(item, active) } }
      when Hash then storage_json_container(value, active) { storage_json_entries(value, active) }
      else raise Error::TransportError, 'invalid storage JSON value'
      end
    end

    def storage_json_container(value, active)
      id = value.object_id
      raise Error::TransportError, 'invalid storage JSON value' if active.key?(id) || active.size >= 100

      active[id] = true
      copy = yield
      active.delete(id)
      copy
    end
  end
end
