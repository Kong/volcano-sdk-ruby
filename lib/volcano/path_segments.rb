# frozen_string_literal: true

module Volcano
  # Keeps caller values inside the route they were written into. libcurl
  # removes "." and ".." segments before sending, and Hosting routes on the
  # decoded path, so "..", "%2e%2e", or an encoded "/" in a value would move a
  # request onto another route with the caller's token. An empty segment can
  # turn an item route into its collection route.
  module PathSegments
    UNSAFE_SEGMENTS = 'cannot contain empty, ".", or ".." segments'
    UNSAFE_REQUEST_PATH = 'Request path cannot contain empty, ".", "..", or encoded "/" segments'
    DOT_SEGMENTS = %w[. ..].freeze
    ENCODED_DOT = /%2e/i
    ENCODED_SLASH = /%2f/i
    private_constant :DOT_SEGMENTS, :ENCODED_DOT, :ENCODED_SLASH

    # Hosting ignores one leading slash, so "/a.txt" and "a.txt" name the same object.
    def self.bucket_relative_path(path)
      path.delete_prefix('/')
    end

    def self.unsafe_storage_path?(path)
      relative = bucket_relative_path(path)
      relative.empty? || relative.split('/', -1).any? { |segment| segment.empty? || DOT_SEGMENTS.include?(segment) }
    end

    # Checks a generated route after its parameters are encoded into it and
    # before a URL is built from it, so every operation shares one guard.
    def self.check_request_path!(path)
      segments = path.delete_prefix('/').split('/', -1)
      raise ArgumentError, UNSAFE_REQUEST_PATH if segments.any? { |segment| unsafe_request_segment?(segment) }

      path
    end

    def self.unsafe_request_segment?(segment)
      segment.empty? || DOT_SEGMENTS.include?(segment.gsub(ENCODED_DOT, '.')) || ENCODED_SLASH.match?(segment)
    end
  end
  private_constant :PathSegments
end
