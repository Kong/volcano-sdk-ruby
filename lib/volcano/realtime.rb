# frozen_string_literal: true

require 'uri'

module Volcano
  class Realtime
    def initialize(client, api_url:, socket_factory: nil)
      @client = client
      @api_url = api_url
      @socket_factory = socket_factory || method(:open_socket)
      @protocol = nil
      @protocol_lock = nil
      @channels = {}
      @closed = false
    end

    def channel(name) = ensure_open!.then { @channels["broadcast:#{name}"] ||= Channel.new(self, "broadcast:#{name}") }

    def protocol
      ensure_open!
      return @protocol if @protocol

      require 'async/semaphore'
      @protocol_lock ||= Async::Semaphore.new(1)
      @protocol_lock.acquire do
        ensure_open!
        return @protocol if @protocol

        socket = @socket_factory.call(address)
        protocol = Protocol.new(socket: socket, secrets: realtime_secrets)
        protocol.connect(token: @client.session_token)
        @protocol = protocol
      rescue StandardError => e
        begin
          socket&.close
        rescue StandardError
          nil
        end
        raise public_error(e), cause: nil
      end
    end

    def disconnect
      @protocol_lock ? @protocol_lock.acquire { close_protocol } : close_protocol
    rescue StandardError => e
      raise public_error(e), cause: nil
    end

    def close_protocol
      return nil if @closed

      @closed = true
      begin
        @protocol&.close
      ensure
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

    def address
      uri = URI(@api_url)
      uri.scheme = uri.scheme == 'https' ? 'wss' : 'ws'
      uri.path = '/realtime/v1/websocket'
      encoded_key = URI.encode_www_form_component(@client.anon_token).gsub('+', '%20')
      uri.query = "apikey=#{encoded_key}"
      uri.to_s
    end

    def open_socket(address)
      require 'async/http/endpoint'
      require 'async/websocket/client'
      Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse(address))
    end

    def realtime_secrets = [@client.anon_token, @client.current_session&.access_token]

    def public_error(error)
      redacted = Redaction.exception(error, secrets: realtime_secrets)
      return redacted unless Transport::NETWORK_ERRORS.any? { |type| error.is_a?(type) }

      transport_error = Error::TransportError.new(redacted.message)
      transport_error.set_backtrace(redacted.backtrace)
      transport_error
    end

    class Channel
      def initialize(realtime, name)
        @realtime = realtime
        @name = name
        @callbacks = []
        @handler_registered = @subscribed = @closed = false
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

          protocol = @realtime.protocol
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
          @realtime.protocol.publish(channel: @name, data: data)
        end
        nil
      end

      def unsubscribe
        with_lifecycle_lock do
          ensure_open!
          next unless @subscribed

          @realtime.protocol.unsubscribe(channel: @name)
          @subscribed = false
        end
        nil
      end

      def mark_closed
        @closed = true
        @lifecycle_lock ? @lifecycle_lock.acquire { @subscribed = false } : @subscribed = false
      end

      private

      def register_handler(protocol)
        return if @handler_registered

        protocol.on_publication(@name) do |event, data|
          @callbacks.each { |callback| callback.call(data) } if event == 'message'
        end
        @handler_registered = true
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
