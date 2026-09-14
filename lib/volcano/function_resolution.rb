# frozen_string_literal: true

require 'uri'

module Volcano
  # Shared cache for function name resolution.
  #
  # GET /functions/resolve maps a function name to the identity and endpoint
  # used to invoke it, and tells us how long that mapping stays valid. Without
  # a cache every invocation pays that round trip. Entries are shared
  # process-wide so separate clients against the same API reuse one resolution,
  # and keyed by credential so a mapping never crosses an identity.
  module FunctionResolution
    Resolution = Data.define(:function_id, :invoke_url)

    # A cached resolve result. A nil resolution is a remembered miss.
    Outcome = Data.define(:resolution)

    Entry = Data.define(:outcome, :expires_at)
    private_constant :Entry

    MAX_ENTRIES = 1024
    NEGATIVE_TTL_SECONDS = 30
    ALLOWED_SCHEMES = %w[http https].freeze
    private_constant :ALLOWED_SCHEMES

    @lock = Mutex.new
    @entries = {}

    class << self
      # Returns an absolute HTTP(S) invocation URL, or nil when unusable.
      #
      # The URL carries the caller's bearer token, so anything that is not a
      # well-formed absolute HTTP(S) URL is discarded rather than requested.
      def valid_invoke_url(value)
        return nil unless value.is_a?(String) && !value.empty?

        uri = URI.parse(value)
        return nil unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase) && !uri.host.to_s.empty?

        value
      rescue URI::InvalidURIError
        nil
      end

      # Returns the cached Outcome for a name, or nil when it must be resolved.
      def lookup(api_url, authorization, name)
        key = [api_url, authorization, name]
        @lock.synchronize do
          entry = @entries[key]
          next nil if entry.nil?

          if entry.expires_at <= now
            @entries.delete(key)
            next nil
          end
          entry.outcome
        end
      end

      # Caches a resolution for the server-advertised lifetime.
      def store(api_url, authorization, name, resolution, ttl_seconds)
        write([api_url, authorization, name], Outcome.new(resolution: resolution), ttl_seconds)
      end

      # Remembers briefly that a name does not resolve, so a caller retrying an
      # unknown name in a loop does not re-ask the server on every attempt.
      def store_missing(api_url, authorization, name)
        write([api_url, authorization, name], Outcome.new(resolution: nil), NEGATIVE_TTL_SECONDS)
      end

      # Drops one cached resolution that turned out to be stale.
      def forget(api_url, authorization, name)
        @lock.synchronize { @entries.delete([api_url, authorization, name]) }
      end

      # Drops every cached resolution. Used by specs for isolation.
      def clear
        @lock.synchronize { @entries.clear }
      end

      # The clock lifetimes are measured against, immune to wall-clock jumps.
      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      private

      def write(key, outcome, ttl_seconds)
        @lock.synchronize do
          @entries[key] = Entry.new(outcome: outcome, expires_at: now + ttl_seconds)
          next if @entries.size <= MAX_ENTRIES

          @entries.delete_if { |_, entry| entry.expires_at <= now }
          @entries.delete(@entries.min_by { |_, entry| entry.expires_at }&.first) while @entries.size > MAX_ENTRIES
        end
      end
    end
  end
end
