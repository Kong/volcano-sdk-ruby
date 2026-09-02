# frozen_string_literal: true

module Volcano
  # Mutation operations for one storage bucket.
  class StorageBucket
    def remove(paths)
      deleted = removal_paths(paths)
      authorization = @client.session_token
      deleted.each { |path| delete_path(path, authorization) }
      deleted
    end

    def move(from_path, to_path)
      source, destination = removal_paths([from_path, to_path])
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
      source, destination = removal_paths([from_path, to_path])
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

    private

    def removal_paths(paths)
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
  end
end
