# frozen_string_literal: true

module Volcano
  # Corrects generated HTTP operations for resumable storage uploads.
  module UploadSessionStorageApi
    CREATE_OPTIONS = {
      operation: :'StorageObjectsApi.upload_storage_object',
      header_params: { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }.freeze,
      auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
      return_type: 'CreateUploadSessionResponse'
    }.freeze
    UPLOAD_PART_OPTIONS = {
      operation: :'StorageObjectsApi.upload_part',
      header_params: { 'Accept' => 'application/json', 'Content-Type' => 'application/octet-stream' }.freeze,
      auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
      return_type: 'UploadSessionPart'
    }.freeze
    COMPLETE_OPTIONS = {
      operation: :'StorageObjectsApi.upload_storage_object',
      header_params: { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }.freeze,
      auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
      return_type: 'CompleteUploadSessionResponse'
    }.freeze
    STATUS_OPTIONS = {
      operation: :'StorageObjectsApi.download_storage_object',
      header_params: { 'Accept' => 'application/json' }.freeze,
      auth_names: %w[ServiceRoleKey AuthUserAccessToken AnonKey].freeze,
      return_type: 'UploadSessionStatusResponse'
    }.freeze
    ABORT_OPTIONS = {
      operation: :'StorageObjectsApi.delete_storage_object',
      header_params: { 'Accept' => 'application/json' }.freeze,
      auth_names: %w[ServiceRoleKey AuthUserAccessToken].freeze
    }.freeze

    def create_upload_session_with_http_info(bucket_name, path, request)
      options = CREATE_OPTIONS.merge(body: api_client.object_to_http_body(request))
      call_storage_api(:POST, bucket_name, path, options)
    end

    def upload_part_with_http_info(bucket_name, path, session_id, part_number, data)
      headers = UPLOAD_PART_OPTIONS.fetch(:header_params).merge(
        'X-Upload-Session' => session_id, 'X-Part-Number' => part_number.to_s
      )
      call_storage_api(
        :PUT, bucket_name, path, UPLOAD_PART_OPTIONS.merge(header_params: headers, body: data)
      )
    end

    def complete_upload_session_with_http_info(bucket_name, path, session_id)
      headers = COMPLETE_OPTIONS.fetch(:header_params).merge(
        'X-Upload-Session' => session_id, 'X-Upload-Complete' => 'true'
      )
      options = COMPLETE_OPTIONS.merge(header_params: headers, body: JSON.generate({}))
      call_storage_api(:POST, bucket_name, path, options)
    end

    def get_upload_session_with_http_info(bucket_name, path, session_id)
      headers = STATUS_OPTIONS.fetch(:header_params).merge('X-Upload-Session' => session_id)
      call_storage_api(:GET, bucket_name, path, STATUS_OPTIONS.merge(header_params: headers))
    end

    def abort_upload_session_with_http_info(bucket_name, path, session_id)
      headers = ABORT_OPTIONS.fetch(:header_params).merge('X-Upload-Session' => session_id)
      call_storage_api(:DELETE, bucket_name, path, ABORT_OPTIONS.merge(header_params: headers))
    end
  end
  private_constant :UploadSessionStorageApi
end
