# frozen_string_literal: true

require 'securerandom'
require 'time'

module Volcano
  # Acquires and releases project-scoped distributed locks.
  class Locks
    include LockAutoRenewal
    include LockResponse

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def get(key, request_id: nil)
      payload = lock_payload(perform_request(200) do
        @transport.get_project_lock(
          authorization: @client.service_token, key: key, request_id: request_uuid(request_id, 'request_id')
        )
      end)
      LockState.new(
        held: lock_held(payload['held']),
        expires_at: parse_time(payload['expires_at']),
        fencing_token: optional_fencing_token(payload['fencing_token'])
      )
    end

    def acquire(key, ttl:, token: nil, request_id: nil)
      validate_ttl(ttl)
      authorization = @client.service_token.dup.freeze
      owned_key = key.dup.freeze
      owned_token = request_uuid(token, 'token')
      owned_request_id = request_uuid(request_id, 'request_id')
      payload = acquire_payload(
        authorization: authorization, key: owned_key, ttl: ttl, token: owned_token, request_id: owned_request_id
      )
      build_lease(owned_key, owned_token, payload)
    end

    def renew(key, lease, ttl:, request_id: nil)
      validate_ttl(ttl)
      payload = lock_payload(perform_request(200) do
        @transport.renew_project_lock(
          authorization: @client.service_token, key: key, ttl: ttl,
          token: lease.token, request_id: request_uuid(request_id, 'request_id')
        )
      end)
      build_lease(key, lease.token, payload)
    end

    def release(key, lease, request_id: nil)
      perform_request(204) do
        @transport.release_project_lock(
          authorization: @client.service_token, key: key, token: lease.token,
          request_id: request_uuid(request_id, 'request_id')
        )
      end
      nil
    end

    def force_release(key, request_id: nil)
      perform_request(204) do
        @transport.force_release_project_lock(
          authorization: @client.service_token, key: key, request_id: request_uuid(request_id, 'request_id')
        )
      end
      nil
    end

    private

    def acquire_payload(authorization:, key:, ttl:, token:, request_id:)
      lock_payload(perform_request(201) do
        @transport.acquire_project_lock(authorization: authorization, key: key, ttl: ttl,
                                        token: token, request_id: request_id)
      end)
    rescue Error::TransportError, Error::ServerError => e
      raise unless e.status.nil? || e.status == 503

      lock_payload(perform_request(201) do
        @transport.acquire_project_lock(authorization: authorization, key: key, ttl: ttl,
                                        token: token, request_id: request_id)
      end)
    end

    def perform_request(status, &)
      response = Transport.invoke(&)
      Transport.body(response, status)
    end

    def request_uuid(value, name)
      return SecureRandom.uuid.freeze if value.nil?

      unless value.is_a?(String) && value.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
        raise ArgumentError, "#{name} must be a UUID string"
      end

      value.dup.freeze
    end

    def build_lease(key, token, payload)
      LockLease.new(
        key: key, token: token, expires_at: parse_time(payload['expires_at']),
        fencing_token: required_fencing_token(payload['fencing_token'])
      )
    end
  end
end
