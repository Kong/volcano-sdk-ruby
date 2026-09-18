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
    Outcome = Data.define(:resolution, :failure)

    Failure = Data.define(:message, :code, :retry_after) do
      def exception
        Error::NotFoundError.new(message.dup, status: 404, code: code&.dup, retry_after: retry_after)
      end
    end
    private_constant :Failure

    Entry = Data.define(:outcome, :expires_at)
    private_constant :Entry

    MAX_ENTRIES = 1024
    NEGATIVE_TTL_SECONDS = 30

    # Concurrent misses for one name serialize on a shared lock rather than
    # each opening its own resolve. Striping keeps that bounded: a per-key lock
    # table would grow with every name ever invoked.
    LOCK_STRIPES = 64
    private_constant :LOCK_STRIPES

    @lock = Mutex.new
    @entries = {}
    @stripes = Array.new(LOCK_STRIPES) { Mutex.new }

    class << self
      # Returns the lock that serializes resolving one name.
      def resolve_lock(api_url, authorization, name)
        @stripes[[api_url, authorization, name].hash % LOCK_STRIPES]
      end

      # Returns an absolute invocation URL, or nil when unusable.
      #
      # The URL carries the caller's bearer token. Plaintext is accepted only
      # when the API itself is plaintext, so a resolve response cannot
      # downgrade a credential that is otherwise protected in transit.
      def valid_invoke_url(value, api_url)
        return nil unless value.is_a?(String) && !value.empty?

        uri = URI.parse(value)
        # URI accepts a port outside the range a connection can use.
        return nil if uri.host.to_s.empty? || !uri.port.to_i.between?(1, 65_535)

        usable_scheme?(uri.scheme, api_url) ? value : nil
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
        write([api_url, authorization, name], Outcome.new(resolution: resolution, failure: nil), ttl_seconds)
      end

      # Remembers briefly that a name does not resolve, so a caller retrying an
      # unknown name in a loop does not re-ask the server on every attempt.
      def store_missing(api_url, authorization, name, error)
        failure = Failure.new(message: error.message.dup.freeze, code: error.code&.dup&.freeze,
                              retry_after: error.retry_after)
        write([api_url, authorization, name], Outcome.new(resolution: nil, failure: failure), NEGATIVE_TTL_SECONDS)
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

      def usable_scheme?(scheme, api_url)
        case scheme&.downcase
        when 'https' then true
        when 'http' then URI.parse(api_url).scheme&.downcase == 'http'
        else false
        end
      end

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
