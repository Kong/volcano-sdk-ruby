# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'json'

module Volcano
  # Local public URL construction for one storage bucket.
  class StorageBucket
    INVALID_PUBLIC_URL_ANON_KEY = 'Anon key must contain a project ID'
    INVALID_PUBLIC_URL_PATH = 'Public URL paths cannot contain dot segments'
    INVALID_STORAGE_PATH = 'storage path must be a non-empty string'
    private_constant :INVALID_PUBLIC_URL_ANON_KEY, :INVALID_PUBLIC_URL_PATH, :INVALID_STORAGE_PATH

    def get_public_url(path)
      object_path = public_url_path(path)
      segments = [project_id, @name, *public_url_path_segments(object_path)]
      "#{@api_url}/public/#{segments.map { |segment| encode_segment(segment) }.join('/')}".freeze
    end

    private

    def project_id
      value = anon_key_payload['project_id']
      return value if value.is_a?(String) && !value.strip.empty?

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

    def public_url_path_segments(path)
      segments = path.split('/', -1)
      raise ArgumentError, INVALID_PUBLIC_URL_PATH if segments.intersect?(%w[. ..])

      segments
    end

    def public_url_path(path)
      return path if path.is_a?(String) && !path.empty?

      raise ArgumentError, INVALID_STORAGE_PATH
    end

    def encode_segment(segment)
      CGI.escapeURIComponent(segment)
    end
  end
end
