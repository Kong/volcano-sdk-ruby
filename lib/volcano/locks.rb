# frozen_string_literal: true

require 'securerandom'
require 'time'

module Volcano
  # Acquires and releases project-scoped distributed locks.
  class Locks
    include LockAutoRenewal

    def initialize(client, transport)
      @client = client
      @transport = transport
    end

    def get(key, request_id: nil)
      payload = lock_request(:get_project_lock, 200, key: key, request_id: request_id)
      LockState.new(
        held: payload.fetch('held'),
        expires_at: parse_time(payload['expires_at']),
        fencing_token: payload['fencing_token']
      )
    end

    def acquire(key, ttl:, token: nil, request_id: nil)
      validate_ttl(ttl)
      parameters = {
        authorization: @client.service_token.dup.freeze, key: key.dup.freeze,
        ttl: ttl, token: request_uuid(token, 'token'), request_id: request_uuid(request_id, 'request_id')
      }.freeze
      payload = acquire_payload(parameters)
      build_lease(parameters[:key], parameters[:token], payload)
    end

    def renew(key, lease, ttl:, request_id: nil)
      validate_ttl(ttl)
      payload = lock_request(:renew_project_lock, 200, key: key, ttl: ttl,
                                                       token: lease.token, request_id: request_id)
      build_lease(key, lease.token, payload)
    end

    def release(key, lease, request_id: nil)
      lock_request(:release_project_lock, 204, key: key, token: lease.token, request_id: request_id)
      nil
    end

    def force_release(key, request_id: nil)
      lock_request(:force_release_project_lock, 204, key: key, request_id: request_id)
      nil
    end

    private

    def acquire_payload(parameters)
      perform_request(:acquire_project_lock, 201, parameters)
    rescue Error::TransportError, Error::ServerError => e
      raise unless e.status.nil? || e.status == 503

      perform_request(:acquire_project_lock, 201, parameters)
    end

    def lock_request(operation, status, **parameters)
      parameters[:authorization] = @client.service_token
      parameters[:request_id] = request_uuid(parameters[:request_id], 'request_id')
      perform_request(operation, status, parameters)
    end

    def perform_request(operation, status, parameters)
      response = Transport.invoke { @transport.public_send(operation, **parameters) }
      Transport.body(response, status)
    end

    def request_uuid(value, name)
      return SecureRandom.uuid.freeze if value.nil?

      valid = value.is_a?(String) && value.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
      raise ArgumentError, "#{name} must be a UUID string" unless valid

      value.dup.freeze
    end

    def build_lease(key, token, payload)
      LockLease.new(
        key: key, token: token, expires_at: parse_time(payload['expires_at']),
        fencing_token: payload['fencing_token']
      )
    end

    def parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end
  end
end
