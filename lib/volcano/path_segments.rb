# frozen_string_literal: true

module Volcano
  # Path segment rules for generated request paths and storage object paths.
  # libcurl and Hosting treat ".", "..", "%2e", and an encoded "/" as path
  # structure, and an empty segment changes which route matches, so these
  # values are rejected before a URL is built.
  module PathSegments
    INVALID_SEGMENTS = 'cannot contain empty, ".", or ".." segments'
    INVALID_REQUEST_PATH = 'Request path cannot contain empty, ".", "..", or encoded "/" segments'
    INVALID_BUCKET_NAME = 'bucket name must be 1-64 letters, numbers, "_", or "-"'
    BUCKET_NAME = /\A[a-zA-Z0-9_-]{1,64}\z/
    DOT_SEGMENTS = %w[. ..].freeze
    ENCODED_DOT = /%2e/i
    ENCODED_SLASH = /%2f/i
    private_constant :BUCKET_NAME, :DOT_SEGMENTS, :ENCODED_DOT, :ENCODED_SLASH

    # The OpenAPI BucketName pattern, anchored to the whole string; the
    # generated client's ^...$ matches any one line of a multi-line value.
    def self.check_bucket_name!(name)
      return name if name.is_a?(String) && BUCKET_NAME.match?(name)

      raise ArgumentError, INVALID_BUCKET_NAME
    end

    # Requires a value that stays a single path segment.
    def self.check_identifier!(value, field)
      return value unless DOT_SEGMENTS.include?(value) || value.include?('/')

      raise ArgumentError, %(#{field} cannot contain "/" or be "." or "..")
    end

    # Hosting ignores one leading slash, so "/a.txt" and "a.txt" name the same object.
    def self.bucket_relative_path(path)
      path.delete_prefix('/')
    end

    def self.invalid_storage_path?(path)
      relative = bucket_relative_path(path)
      relative.empty? || relative.split('/', -1).any? { |segment| segment.empty? || DOT_SEGMENTS.include?(segment) }
    end

    # Checks a generated route after its parameters are encoded into it and
    # before a URL is built from it, so every operation shares one guard.
    def self.check_request_path!(path)
      segments = path.delete_prefix('/').split('/', -1)
      raise ArgumentError, INVALID_REQUEST_PATH if segments.any? { |segment| invalid_request_segment?(segment) }

      path
    end

    def self.invalid_request_segment?(segment)
      segment.empty? || DOT_SEGMENTS.include?(segment.gsub(ENCODED_DOT, '.')) || ENCODED_SLASH.match?(segment)
    end
  end
  private_constant :PathSegments
end
