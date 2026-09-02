# frozen_string_literal: true

require 'uri'
require_relative 'realtime/connection_callbacks'
require_relative 'realtime/connection'
require_relative 'realtime/lifecycle'
require_relative 'realtime/presence_state'
require_relative 'realtime/presence'
require_relative 'realtime/channel_callbacks'

module Volcano
  # Manages a project's realtime connection and broadcast channels.
  class Realtime
    include Lifecycle
    include ConnectionCallbacks
    include Connection

    ConnectContext = Data.define(:client)
    DisconnectContext = Data.define(:code, :reason)
    ErrorContext = Data.define(:code, :message, :error)

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

    CHANNEL_TYPES = %i[broadcast presence].freeze

    def initialize(client, api_url:, socket_factory: nil)
      @client = client
      @api_url = api_url
      @socket_factory = socket_factory || method(:open_socket)
      @protocol = nil
      @protocol_lock = nil
      @channel_lock = nil
      @channels = {}
      @connection_callbacks = { connect: {}, disconnect: {}, error: {} }
      @next_connection_callback_id = 0
      @closed = false
    end

    def channel(name, type: :broadcast)
      type = normalize_channel_type(type)
      channel_lock.acquire do
        ensure_open!
        channel_name = "#{type}:#{name}"
        @channels[channel_name] ||= Channel.new(
          self,
          method(:protocol),
          channel_name,
          type
        )
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

    def close_protocol
      return nil if @closed

      @closed = true
      begin
        @manual_disconnect = true
        @protocol&.close
      ensure
        @manual_disconnect = false
        @channels.each_value(&:mark_closed)
      end
      nil
    end

    def ensure_open!
      raise ClosedError, 'realtime connection closed' if @closed

      self
    end

    private :close_protocol

    private

    def normalize_channel_type(type)
      normalized = type.to_s.to_sym
      return normalized if CHANNEL_TYPES.include?(normalized)

      raise ArgumentError, "unsupported realtime channel type: #{type}"
    end

    def report_channel_error(error) = protocol_error(public_error(error))

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
      include PresenceState
      include Presence
      include ChannelCallbacks

      attr_reader :name

      def initialize(realtime, protocol_provider, name, type)
        @realtime = realtime
        @protocol_provider = protocol_provider
        @name = name.freeze
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @handler_registered = @subscribed = @closed = false
        @publication_handler = nil
        @lifecycle_lock = nil
        @callback_lock = nil
        initialize_presence(type)
      end

      def subscribe
        with_lifecycle_lock do
          ensure_open!
          raise DuplicateSubscriptionError, "already subscribed to #{@name}" if @subscribed

          protocol = @protocol_provider.call
          subscribe_protocol(protocol)
        end
        nil
      end

      def send(event:, **payload)
        with_lifecycle_lock do
          ensure_open!
          raise ClosedError, 'realtime channel is not subscribed' unless @subscribed
          raise ArgumentError, 'send is only available for broadcast channels' if presence?

          data = { 'event' => event.to_s, **payload.transform_keys(&:to_s) }
          @protocol_provider.call.publish(channel: @name, data: data)
        end
        nil
      end

      def unsubscribe
        with_lifecycle_lock do
          ensure_open!
          next unless @subscribed

          protocol = @protocol_provider.call
          protocol.unsubscribe(channel: @name)
          @subscribed = false
          invalidate_presence_subscription(protocol)
          clear_presence
        end
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

      def mark_closed
        @closed = true
        @subscribed = false
        reset_presence
      end

      private

      def subscribe_protocol(protocol)
        epoch = next_presence_epoch
        register_handlers(protocol, epoch)
        protocol.subscribe(channel: @name, recoverable: presence?, join_leave: presence?)
        @subscribed = true
        sync_presence(protocol, epoch)
      rescue StandardError
        invalidate_presence_subscription(protocol)
        raise
      end

      def detach_from_protocol
        return unless @subscribed || @publication_handler

        protocol = @protocol_provider.call
        protocol.unsubscribe(channel: @name) if @subscribed && protocol.connected?
        detach_publication_handler(protocol)
      end

      def mark_removed
        @callbacks.each_value(&:clear)
        @handler_registered = @subscribed = false
        reset_presence
        @closed = true
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
