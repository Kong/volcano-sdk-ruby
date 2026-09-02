# frozen_string_literal: true

module Volcano
  # Mutation operations for one storage bucket.
  class StorageBucket
    def remove(paths)
      deleted = storage_paths(paths)
      authorization = @client.session_token
      deleted.each { |path| delete_path(path, authorization) }
      deleted
    end

    def move(from_path, to_path)
      source, destination = storage_paths([from_path, to_path])
      response = Transport.invoke do
        @transport.move_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          from_path: source,
          to_path: destination
        )
      end
      storage_object(Transport.body(response, 200))
    end

    def copy(from_path, to_path)
      source, destination = storage_paths([from_path, to_path])
      response = Transport.invoke do
        @transport.copy_storage_object(
          authorization: @client.session_token,
          bucket_name: @name,
          from_path: source,
          to_path: destination
        )
      end
      storage_object(Transport.body(response, 201))
    end

    def update_visibility(path, public:)
      object_path = storage_paths(path).fetch(0)
      visibility = visibility_value(public)
      response = Transport.invoke do
        @transport.update_storage_object_visibility(
          authorization: @client.session_token,
          bucket_name: @name,
          path: object_path,
          is_public: visibility
        )
      end
      storage_object(Transport.body(response, 200))
    end

    private

    def storage_paths(paths)
      path_list = paths.is_a?(String) ? [paths] : paths.to_a
      if path_list.empty? || !path_list.all? { |path| path.is_a?(String) && !path.empty? }
        raise ArgumentError, 'storage paths must be non-empty strings'
      end

      path_list.map { |path| path.dup.freeze }.freeze
    end

    def delete_path(path, authorization)
      response = Transport.invoke do
        @transport.delete_storage_object(
          authorization: authorization,
          bucket_name: @name,
          path: path
        )
      end
      Transport.body(response, 200)
    end

    def visibility_value(value)
      return value if [true, false].include?(value)

      raise ArgumentError, 'public must be true or false'
    end
  end
end
