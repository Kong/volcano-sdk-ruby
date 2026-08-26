# frozen_string_literal: true

require 'async/http/endpoint'
require 'async/websocket/client'
require 'uri'

module Volcano
  class Realtime
    def initialize(client, api_url:, socket_factory: nil)
      @client = client
      @api_url = api_url
      @socket_factory = socket_factory || method(:open_socket)
      @protocol = nil
      @channels = {}
      @closed = false
    end

    def channel(name)
      ensure_open!
      wire_name = "broadcast:#{name}"
      @channels[wire_name] ||= Channel.new(self, wire_name)
    end

    def protocol
      ensure_open!
      return @protocol if @protocol

      socket = @socket_factory.call(address)
      @protocol = Protocol.new(socket: socket)
      @protocol.connect(token: @client.session_token)
      @protocol
    rescue StandardError
      socket&.close
      @protocol = nil
      raise
    end

    def disconnect
      return nil if @closed

      @closed = true
      @protocol&.close
      @channels.each_value(&:mark_closed)
      nil
    end

    def ensure_open!
      raise ClosedError, 'realtime connection closed' if @closed
    end

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
      endpoint = Async::HTTP::Endpoint.parse(address)
      Async::WebSocket::Client.connect(endpoint)
    end

    class Channel
      def initialize(realtime, name)
        @realtime = realtime
        @name = name
        @callbacks = []
        @handler_registered = false
        @subscribed = false
        @closed = false
      end

      def on(event, callback = nil, &block)
        raise ArgumentError, "unsupported realtime event: #{event}" unless event == 'message'

        @callbacks << (callback || block || raise(ArgumentError, 'callback or block is required'))
        self
      end

      def subscribe
        ensure_open!
        raise DuplicateSubscriptionError, "already subscribed to #{@name}" if @subscribed

        protocol = @realtime.protocol
        register_handler(protocol)
        protocol.subscribe(channel: @name)
        @subscribed = true
        nil
      end

      def send(event:, **payload)
        ensure_open!
        raise ClosedError, 'realtime channel is not subscribed' unless @subscribed

        data = { 'event' => event.to_s, **payload.transform_keys(&:to_s) }
        @realtime.protocol.publish(channel: @name, data: data)
        nil
      end

      def unsubscribe
        ensure_open!
        return nil unless @subscribed

        @realtime.protocol.unsubscribe(channel: @name)
        @subscribed = false
        nil
      end

      def mark_closed
        @closed = true
        @subscribed = false
      end

      private

      def register_handler(protocol)
        return if @handler_registered

        protocol.on_publication(@name) do |event, data|
          @callbacks.each { |callback| callback.call(data) } if event == 'message'
        end
        @handler_registered = true
      end

      def ensure_open!
        raise ClosedError, 'realtime connection closed' if @closed

        @realtime.ensure_open!
      end
    end
  end
end
