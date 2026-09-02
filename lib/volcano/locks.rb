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

    def get(key)
      payload = Transport.body(get_response(key), 200)
      LockState.new(
        held: payload.fetch('held'),
        expires_at: parse_time(payload['expires_at']),
        fencing_token: payload['fencing_token']
      )
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

    def renew(key, lease, ttl:)
      payload = Transport.body(renew_response(key, lease, ttl), 200)
      LockLease.new(
        key: key,
        token: lease.token,
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

    def force_release(key)
      Transport.body(force_release_response(key), 204)
      nil
    end

    private

    def get_response(key)
      Transport.invoke do
        @transport.get_project_lock(
          authorization: @client.service_token,
          key: key
        )
      end
    end

    def force_release_response(key)
      Transport.invoke do
        @transport.force_release_project_lock(
          authorization: @client.service_token,
          key: key
        )
      end
    end

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

    def renew_response(key, lease, ttl)
      Transport.invoke do
        @transport.renew_project_lock(
          authorization: @client.service_token,
          key: key,
          ttl: ttl,
          token: lease.token
        )
      end
    end

    def parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end
  end
end
