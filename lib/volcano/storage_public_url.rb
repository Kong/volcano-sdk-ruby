# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'json'

module Volcano
  # Local public URL construction for one storage bucket.
  class StorageBucket
    INVALID_PUBLIC_URL_ANON_KEY = 'Anon key must contain a project ID'
    INVALID_STORAGE_PATH = 'storage path must be a non-empty string'
    private_constant :INVALID_PUBLIC_URL_ANON_KEY, :INVALID_STORAGE_PATH

    def get_public_url(path)
      object_path = public_url_path(path)
      bucket = PathSegments.check_bucket_name!(@name)
      segments = [project_id, bucket, *PathSegments.bucket_relative_path(object_path).split('/')]
      "#{@api_url}/public/#{segments.map { |segment| encode_segment(segment) }.join('/')}".freeze
    end

    private

    def project_id
      value = anon_key_payload['project_id']
      if value.is_a?(String) && !value.strip.empty?
        return PathSegments.check_identifier!(value,
                                              'Project ID in anon key')
      end

      raise ArgumentError, INVALID_PUBLIC_URL_ANON_KEY
    end

    def anon_key_payload
      parts = @anon_key.split('.')
      raise ArgumentError, INVALID_PUBLIC_URL_ANON_KEY unless parts.length == 3

      encoded = parts.fetch(1).tr('-_', '+/')
      payload = JSON.parse(Base64.strict_decode64(pad_base64(encoded)))
      return payload if payload.is_a?(Hash)

      raise ArgumentError, INVALID_PUBLIC_URL_ANON_KEY
    rescue ArgumentError, JSON::ParserError => e
      raise ArgumentError, INVALID_PUBLIC_URL_ANON_KEY, cause: e
    end

    def pad_base64(encoded)
      encoded + ('=' * (-encoded.length % 4))
    end

    def public_url_path(path)
      raise ArgumentError, INVALID_STORAGE_PATH unless path.is_a?(String) && !path.empty?
      raise ArgumentError, "storage path #{PathSegments::INVALID_SEGMENTS}" if PathSegments.invalid_storage_path?(path)

      path
    end

    def encode_segment(segment)
      CGI.escapeURIComponent(segment)
    end
  end
end
