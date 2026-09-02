# frozen_string_literal: true

require 'uri'
require_relative 'realtime/connection_callbacks'
require_relative 'realtime/connection'
require_relative 'realtime/lifecycle'

module Volcano
  # Manages a project's realtime connection and broadcast channels.
  class Realtime
    include Lifecycle
    include ConnectionCallbacks
    include Connection

    ConnectContext = Data.define(:client)
    DisconnectContext = Data.define(:code, :reason)
    ErrorContext = Data.define(:code, :message, :error)

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

    def channel(name)
      channel_lock.acquire do
        ensure_open!
        @channels["broadcast:#{name}"] ||= Channel.new(
          self,
          method(:protocol),
          "broadcast:#{name}"
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
      attr_reader :name

      def initialize(realtime, protocol_provider, name)
        @realtime = realtime
        @protocol_provider = protocol_provider
        @name = name.freeze
        @callbacks = []
        @handler_registered = @subscribed = @closed = false
        @publication_handler = nil
        @lifecycle_lock = nil
      end

      def on(event, callback = nil, &block)
        raise ArgumentError, "unsupported realtime event: #{event}" unless event == 'message'

        @callbacks << (callback || block || raise(ArgumentError, 'callback or block is required'))
        self
      end

      def subscribe
        with_lifecycle_lock do
          ensure_open!
          raise DuplicateSubscriptionError, "already subscribed to #{@name}" if @subscribed

          protocol = @protocol_provider.call
          register_handler(protocol)
          protocol.subscribe(channel: @name)
          @subscribed = true
        end
        nil
      end

      def send(event:, **payload)
        with_lifecycle_lock do
          ensure_open!
          raise ClosedError, 'realtime channel is not subscribed' unless @subscribed

          data = { 'event' => event.to_s, **payload.transform_keys(&:to_s) }
          @protocol_provider.call.publish(channel: @name, data: data)
        end
        nil
      end

      def unsubscribe
        with_lifecycle_lock do
          ensure_open!
          next unless @subscribed

          @protocol_provider.call.unsubscribe(channel: @name)
          @subscribed = false
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
        @lifecycle_lock ? @lifecycle_lock.acquire { @subscribed = false } : @subscribed = false
      end

      private

      def register_handler(protocol)
        return if @handler_registered

        @publication_handler = protocol.on_publication(@name) do |event, data|
          @callbacks.each { |callback| callback.call(data) } if event == 'message'
        end
        @handler_registered = true
      end

      def detach_publication_handler(protocol)
        protocol.off_publication(@name, @publication_handler) if @publication_handler
        @publication_handler = nil
      end

      def detach_from_protocol
        return unless @subscribed || @publication_handler

        protocol = @protocol_provider.call
        protocol.unsubscribe(channel: @name) if @subscribed && protocol.connected?
        detach_publication_handler(protocol)
      end

      def mark_removed
        @callbacks.clear
        @handler_registered = @subscribed = false
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
