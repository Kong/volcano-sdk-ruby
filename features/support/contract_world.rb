# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'securerandom'

module VolcanoContract
  Outcome = Data.define(:ok, :value, :category, :error)

  class CleanupError < StandardError
    attr_reader :failures

    def initialize(failures)
      super("Ruby contract cleanup failed: #{failures.map(&:message).join('; ')}")
      @failures = failures.freeze
    end
  end

  ERROR_CATEGORIES = {
    Volcano::Error::AuthenticationError => 'authentication error',
    Volcano::Error::ValidationError => 'validation error',
    Volcano::Error::NotFoundError => 'not found',
    Volcano::Error::ConflictError => 'conflict',
    Volcano::Error::RateLimitedError => 'rate limited',
    Volcano::Error::ServerError => 'server error',
    Volcano::Error::TransportError => 'transport error'
  }.freeze
  STATUS_CATEGORIES = {
    400 => 'validation error',
    401 => 'authentication error',
    403 => 'authentication error',
    404 => 'not found',
    409 => 'conflict',
    422 => 'validation error',
    429 => 'rate limited'
  }.freeze

  CREDENTIAL_KEYS = %w[anon_key service_key user_password].freeze

  def self.classify_error(error)
    category = ERROR_CATEGORIES.find { |error_type, _| error.is_a?(error_type) }&.last
    return category if category
    return 'transport error' unless error.is_a?(Volcano::Error::VolcanoError)

    return 'server error' if (500..599).cover?(error.status)

    STATUS_CATEGORIES.fetch(error.status, 'transport error')
  end

  def self.redact_error(error, fixture)
    redaction = Volcano.const_get(:Redaction, false)
    secrets = CREDENTIAL_KEYS.filter_map { |key| fixture[key] }
    redaction.exception(error, secrets: secrets)
  end

  class World
    attr_accessor :client, :last_outcome, :previous_session, :subscriber, :publisher
    attr_reader :fixture, :service_client, :storage_path, :storage_bytes,
                :realtime_channel, :realtime_message, :lock_key, :realtime_clients

    def initialize(fixture)
      @fixture = fixture
      initialize_clients
      initialize_resource_names
      @last_outcome = nil
      @previous_session = nil
      @realtime_clients = []
      @cleanup_callbacks = []
    end

    def authenticate(client = @client)
      client.auth.sign_in(
        email: fixture.fetch('user_email'),
        password: fixture.fetch('user_password')
      )
    rescue StandardError => e
      raise VolcanoContract.redact_error(e, fixture), cause: nil
    end

    def record
      @last_outcome = Outcome.new(ok: true, value: yield, category: nil, error: nil)
    rescue StandardError => e
      @last_outcome = Outcome.new(
        ok: false,
        value: nil,
        category: VolcanoContract.classify_error(e),
        error: VolcanoContract.redact_error(e, fixture)
      )
    end

    def register_lock_cleanup(key, lease)
      callback = -> { service_client.locks.release(key, lease) }
      @cleanup_callbacks << callback
      callback
    end

    def remove_cleanup(callback)
      @cleanup_callbacks.delete(callback)
    end

    def cleanup
      failures = []
      @cleanup_callbacks.reverse_each { |callback| safely(failures, &callback) }
      @realtime_clients.reverse_each do |client|
        safely(failures) { client.realtime.disconnect }
      end
      @cleanup_callbacks.clear
      @realtime_clients.clear
      raise CleanupError, failures unless failures.empty?
    end

    private

    def initialize_clients
      client_options = { api_url: fixture.fetch('api_url'), anon_key: fixture.fetch('anon_key') }
      @client = Volcano::Client.new(**client_options)
      @service_client = Volcano::Client.new(**client_options, service_key: fixture.fetch('service_key'))
    end

    def initialize_resource_names
      suffix = "rb-#{Process.pid}-#{SecureRandom.hex(5)}"
      @storage_path = "#{fixture.fetch('storage_path')}.#{suffix}"
      @storage_bytes = "volcano-sdk-contract-#{suffix}".b
      @realtime_channel = "#{fixture.fetch('realtime_channel')}-#{suffix}"
      @realtime_message = { 'event' => 'message', 'value' => "volcano-sdk-contract-#{suffix}" }.freeze
      @lock_key = "#{fixture.fetch('lock_key')}-#{suffix}"
    end

    def safely(failures)
      yield
    rescue StandardError => e
      failures << VolcanoContract.redact_error(e, fixture)
    end
  end
end
