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

  def self.classify_error(error)
    ERROR_CATEGORIES.each do |error_type, category|
      return category if error.is_a?(error_type)
    end
    return 'transport error' unless error.is_a?(Volcano::Error::VolcanoError)

    case error.status
    when 401, 403 then 'authentication error'
    when 400, 422 then 'validation error'
    when 404 then 'not found'
    when 409 then 'conflict'
    when 429 then 'rate limited'
    when 500..599 then 'server error'
    else 'transport error'
    end
  end

  class World
    attr_accessor :last_outcome, :subscriber, :publisher
    attr_reader :fixture, :client, :service_client, :storage_path, :storage_bytes,
                :realtime_channel, :realtime_message, :lock_key, :realtime_clients

    def initialize(fixture)
      @fixture = fixture
      @client = Volcano::Client.new(api_url: fixture.fetch('api_url'), anon_key: fixture.fetch('anon_key'))
      @service_client = Volcano::Client.new(
        api_url: fixture.fetch('api_url'),
        anon_key: fixture.fetch('anon_key'),
        service_key: fixture.fetch('service_key')
      )
      suffix = "rb-#{Process.pid}-#{SecureRandom.hex(5)}"
      @storage_path = "#{fixture.fetch('storage_path')}.#{suffix}"
      @storage_bytes = "volcano-sdk-contract-#{suffix}".b
      @realtime_channel = "#{fixture.fetch('realtime_channel')}-#{suffix}"
      @realtime_message = { 'event' => 'message', 'value' => "volcano-sdk-contract-#{suffix}" }.freeze
      @lock_key = "#{fixture.fetch('lock_key')}-#{suffix}"
      @last_outcome = nil
      @realtime_clients = []
      @cleanup_callbacks = []
    end

    def authenticate(client = @client)
      client.auth.sign_in(
        email: fixture.fetch('user_email'),
        password: fixture.fetch('user_password')
      )
    end

    def record
      @last_outcome = Outcome.new(ok: true, value: yield, category: nil, error: nil)
    rescue StandardError => e
      @last_outcome = Outcome.new(
        ok: false,
        value: nil,
        category: VolcanoContract.classify_error(e),
        error: e
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

    def safely(failures)
      yield
    rescue StandardError => e
      failures << e
    end
  end
end
