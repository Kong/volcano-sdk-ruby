# frozen_string_literal: true

require 'securerandom'
require 'time'

module Volcano
  # Acquires and releases project-scoped distributed locks.
  class Locks
    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def acquire(key, ttl:)
      token = SecureRandom.uuid
      payload = Transport.body(acquire_response(key, ttl, token), 201)
      LockLease.new(
        key: key,
        token: token,
        expires_at: parse_time(payload['expires_at']),
        fencing_token: payload['fencing_token']
      )
    end

    def release(key, lease)
      response = Transport.invoke do
        @transport.release_project_lock(
          authorization: @client.service_token,
          key: key,
          token: lease.token
        )
      end
      Transport.body(response, 204)
      nil
    end

    private

    def acquire_response(key, ttl, token)
      Transport.invoke do
        @transport.acquire_project_lock(
          authorization: @client.service_token,
          key: key,
          ttl: ttl,
          token: token
        )
      end
    end

    def parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end
  end
end
