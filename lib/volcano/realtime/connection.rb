# frozen_string_literal: true

module Volcano
  class Realtime
    # Opens the WebSocket transport and maps its failures to public errors.
    module Connection
      private

      def connect_protocol
        socket = @socket_factory.call(address)
        protocol = build_protocol(socket)
        result = protocol.connect(token: @client.session_token)
        @protocol = protocol
        protocol_connected(result)
        protocol
      rescue StandardError
        close_socket(socket)
        raise
      end

      def build_protocol(socket)
        Protocol.new(
          socket: socket,
          secrets: realtime_secrets,
          events: Protocol::Events.new(
            on_close: method(:protocol_closed),
            on_error: method(:protocol_error)
          )
        )
      end

      def close_socket(socket)
        socket&.close
      rescue StandardError
        nil
      end

      def address
        uri = URI(@api_url)
        uri.scheme = uri.scheme == 'https' ? 'wss' : 'ws'
        uri.path = "#{uri.path.delete_suffix('/')}/realtime/v1/websocket"
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
    end
    private_constant :Connection
  end
end
