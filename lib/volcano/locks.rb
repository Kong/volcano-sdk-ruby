# frozen_string_literal: true

require 'securerandom'
require 'time'

module Volcano
  class Locks
    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def acquire(key, ttl:)
      token = SecureRandom.uuid
      response = Transport.invoke do
        @transport.acquire_project_lock(
          authorization: @client.service_token,
          key: key,
          ttl: ttl,
          token: token
        )
      end
      payload = Transport.body(response, 201)
      expires_at = payload['expires_at']
      expires_at = Time.iso8601(expires_at) if expires_at.is_a?(String)
      LockLease.new(
        key: key,
        token: token,
        expires_at: expires_at,
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
  end
end
