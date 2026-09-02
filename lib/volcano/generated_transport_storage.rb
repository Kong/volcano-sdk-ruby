# frozen_string_literal: true

module Volcano
  # Storage operations for the internal generated transport.
  class GeneratedTransport
    def upload_storage_object(authorization:, bucket_name:, path:, data:)
      invoke do
        apis = @api_factory.call(authorization)
        with_upload_file(path, data) do |file|
          result = apis.storage.upload_storage_object_with_http_info(bucket_name, path, file)
          data_value, status, headers = result
          return response(data_value, status, headers)
        end
      end
    end

    def download_storage_object(authorization:, bucket_name:, path:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.download_storage_object_with_http_info(bucket_name, path)
        response(nil, status, headers, binary: binary_data(data))
      end
    end

    def list_storage_objects(authorization:, bucket_name:, prefix:, limit:, cursor:)
      invoke do
        apis = @api_factory.call(authorization)
        options = { prefix: prefix.empty? ? nil : prefix, limit: limit, cursor: cursor }.compact
        data, status, headers = apis.storage.list_storage_objects_with_http_info(bucket_name, options)
        response(data, status, headers)
      end
    end

    def delete_storage_object(authorization:, bucket_name:, path:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.storage.delete_storage_object_with_http_info(bucket_name, path)
        response(data, status, headers)
      end
    end

    def move_storage_object(authorization:, bucket_name:, from_path:, to_path:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::StorageMoveRequest.new(from: from_path, to: to_path)
        data, status, headers = apis.storage.move_storage_object_with_http_info(bucket_name, request)
        response(data, status, headers)
      end
    end

    def copy_storage_object(authorization:, bucket_name:, from_path:, to_path:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::StorageCopyRequest.new(from: from_path, to: to_path)
        data, status, headers = apis.storage.copy_storage_object_with_http_info(bucket_name, request)
        response(data, status, headers)
      end
    end

    private

    def with_upload_file(path, data)
      Tempfile.create(['volcano-sdk-upload', File.extname(path)], binmode: true) do |file|
        file.write(data)
        file.flush
        yield file
      end
    end
  end
end
