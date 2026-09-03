# frozen_string_literal: true

require 'uri'
require_relative 'realtime/connection_callbacks'
require_relative 'realtime/connection'
require_relative 'realtime/reconnect'
require_relative 'realtime/lifecycle'
require_relative 'realtime/channel_lifecycle'
require_relative 'realtime/presence_state'
require_relative 'realtime/presence'
require_relative 'realtime/postgres_database'
require_relative 'realtime/blocking_call'
require_relative 'realtime/postgres_changes'
require_relative 'realtime/postgres_expansion'
require_relative 'realtime/postgres_batch'
require_relative 'realtime/postgres_delivery'
require_relative 'realtime/channel_callbacks'

module Volcano
  # Manages a project's realtime connection and broadcast channels.
  class Realtime
    include Lifecycle
    include ConnectionCallbacks
    include Connection
    include Reconnect
    include PostgresDatabase

    ConnectContext = Data.define(:client)
    DisconnectContext = Data.define(:code, :reason)
    ErrorContext = Data.define(:code, :message, :error)
    PublicationContext = Data.define(:protocol, :publication, :generation, :recovered)
    private_constant :PublicationContext

    # Recursively snapshots JSON-compatible values for callback and state safety.
    module Immutable
      module_function

      def call(value)
        case value
        when Hash then value.to_h { |key, child| [call(key), call(child)] }.freeze
        when Array then value.map { |child| call(child) }.freeze
        when String then value.dup.freeze
        else value.freeze
        end
      end
    end
    private_constant :Immutable

    PresenceInfo = Data.define(:client, :user, :data) do
      def initialize(client:, user: nil, data: {})
        super(
          client: Immutable.call(client.to_s),
          user: user.nil? ? nil : Immutable.call(user.to_s),
          data: Immutable.call(data)
        )
      end
    end

    CHANNEL_TYPES = %i[broadcast presence postgres].freeze

    def initialize(client, api_url:, socket_factory: nil, reconnect_delay: nil)
      @client = client
      @api_url = api_url
      @socket_factory = socket_factory || method(:open_socket)
      @reconnect_delay = reconnect_delay || method(:default_reconnect_delay)
      initialize_realtime_state
      initialize_postgres_database
    end

    def initialize_realtime_state
      @protocol = nil
      @protocol_lock = nil
      @channel_lock = nil
      @channels = {}
      @connection_callbacks = { connect: {}, disconnect: {}, error: {} }
      @next_connection_callback_id = 0
      @protocol_user_id = nil
      @reconnect_task = nil
      @closed = false
    end
    private :initialize_realtime_state

    def channel(
      name, type: :broadcast, auto_fetch: true,
      fetch_batch_window_ms: 20, fetch_max_batch_size: 50
    )
      type = normalize_channel_type(type)
      batch_config = PostgresBatchConfig.new(
        auto_fetch:, batch_window_ms: fetch_batch_window_ms,
        max_batch_size: fetch_max_batch_size
      )
      channel_lock.acquire do
        ensure_open!
        channel_name = "#{type}:#{name}"
        channel = @channels[channel_name]
        next cached_channel(channel, batch_config) if channel

        @channels[channel_name] = build_channel(channel_name, type, batch_config)
      end
    end

    def protocol
      ensure_open!
      return @protocol if @protocol

      protocol_lock.acquire do
        ensure_open!
        @protocol ||= connect_protocol
      end
    rescue StandardError => e
      raise public_error(e), cause: nil
    end
    private :protocol

    def disconnect
      @protocol_lock ? @protocol_lock.acquire { close_protocol } : close_protocol
    rescue StandardError => e
      raise public_error(e), cause: nil
    end

    def ensure_open!
      raise ClosedError, 'realtime connection closed' if @closed

      self
    end

    private

    def normalize_channel_type(type)
      normalized = type.to_s.to_sym
      return normalized if CHANNEL_TYPES.include?(normalized)

      raise ArgumentError, "unsupported realtime channel type: #{type}"
    end

    def report_channel_error(error) = protocol_error(public_error(error))

    def cached_channel(channel, batch_config)
      channel.__send__(:ensure_fetch_config!, batch_config)
      channel
    end

    def build_channel(name, type, batch_config)
      Channel.new(self, method(:protocol), name, type, batch_config:)
    end

    def protocol_lock
      require 'async/semaphore'
      @protocol_lock ||= Async::Semaphore.new(1)
    end

    def channel_lock
      require 'async/semaphore'
      @channel_lock ||= Async::Semaphore.new(1)
    end

    # Represents one realtime broadcast channel.
    class Channel
      include ChannelLifecycle
      include PresenceState
      include Presence
      include PostgresChanges
      include PostgresExpansion
      include PostgresBatch
      include PostgresDelivery
      include ChannelCallbacks

      attr_reader :name

      def initialize(realtime, protocol_provider, name, type, batch_config:)
        @realtime = realtime
        @protocol_provider = protocol_provider
        @name = name.freeze
        @handler_registered = @subscribed = @subscription_desired = @closed = false
        @lifecycle_lock = nil
        @stream_position = {}.freeze
        @stream_lineage = nil
        initialize_callback_dispatch
        initialize_presence(type)
        initialize_postgres_delivery(batch_config)
      end

      def subscribe
        protocol, epoch = with_lifecycle_lock { subscribe_with_intent }
        sync_presence(protocol, epoch)
        nil
      end

      def send(event:, **payload)
        with_lifecycle_lock do
          ensure_open!
          raise ClosedError, 'realtime channel is not subscribed' unless @subscribed
          raise ArgumentError, 'send is only available for broadcast channels' unless broadcast?

          data = { 'event' => event.to_s, **payload.transform_keys(&:to_s) }
          @protocol_provider.call.publish(channel: @name, data: data)
        end
        nil
      end

      def unsubscribe
        state = with_lifecycle_lock { unsubscribe_protocol }
        emit_presence_sync(state)
        nil
      end

      def subscription_desired? = @subscription_desired && !@closed

      def restoration_needed? = subscription_desired? && !@subscribed

      def restore_subscription(protocol)
        state = with_lifecycle_lock do
          next unless restoration_needed?

          subscribe_protocol(protocol)
        end
        sync_presence(*state) if state
        nil
      end

      def remove
        with_lifecycle_lock do
          ensure_open!
          detach_from_protocol
          mark_removed
        end
        nil
      end
      private :remove

      private

      def subscribe_with_intent
        ensure_open!
        raise DuplicateSubscriptionError, "already subscribed to #{@name}" if @subscription_desired

        @subscription_desired = true
        protocol = @protocol_provider.call
        subscribe_protocol(protocol)
      rescue StandardError
        @subscription_desired = false unless protocol && !protocol.connected?
        raise
      end

      def with_lifecycle_lock(&)
        require 'async/semaphore'
        @lifecycle_lock ||= Async::Semaphore.new(1)
        @lifecycle_lock.acquire(&)
      end

      def ensure_open!
        raise ClosedError, 'realtime connection closed' if @closed

        @realtime.ensure_open!
      end
    end
  end
end
