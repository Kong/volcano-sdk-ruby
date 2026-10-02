# frozen_string_literal: true

module Volcano
  class Realtime
    # Opens the WebSocket transport and maps its failures to public errors.
    module Connection
      # @dynamic protocol_connected, protocol_error, protocol_closed, protocol_error_started
      # @dynamic protocol_failed, stop_reconnect

      private

      def connect_protocol
        @protocol_error_reported = false
        session_lineage = active_session_lineage
        socket = @socket_factory.call(address)
        session = session_for_lineage(session_lineage)
        protocol = build_protocol(socket)
        result = protocol.connect(token: session.access_token)
        session_for_lineage(session_lineage)
        activate_protocol(protocol, session_lineage, result)
      rescue StandardError => e
        handle_connection_failure(socket, e)
      end

      def active_session_lineage
        _, lineage, session = @client.capture_session_binding
        raise Error::AuthenticationError, 'No active session' unless session

        session_for_lineage(lineage)
        lineage
      end

      def session_for_lineage(expected_lineage)
        _, lineage, session = @client.capture_session_binding
        return session if session && lineage == expected_lineage

        raise Error::SessionChangedError
      end

      def activate_protocol(protocol, session_lineage, result)
        @protocol = protocol
        @protocol_session_lineage = session_lineage
        protocol_connected(result)
        protocol
      end

      def close_protocol
        return nil if @closed

        @closed = true
        stop_reconnect
        close_connected_protocol
        nil
      end

      def close_connected_protocol
        @manual_disconnect = true
        @protocol&.close
      ensure
        @manual_disconnect = false
        @channels.each_value(&:mark_closed)
        @protocol_session_lineage = nil
      end

      def handle_connection_failure(socket, error)
        failure = public_error(error)
        protocol_error(failure) unless @protocol_error_reported
        close_socket(socket)
        raise failure, cause: nil
      end

      def build_protocol(socket)
        Protocol.new(
          socket: socket,
          secrets: realtime_secrets,
          events: Protocol::Events.new(
            on_close: ->(error) { protocol_closed(error) },
            on_error: ->(error) { protocol_error_started(error) },
            on_failure: ->(error, disconnected) { protocol_failed(error, disconnected) }
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
        uri.path = "#{uri.path.to_s.delete_suffix('/')}/realtime/v1/websocket"
        encoded_key = URI.encode_www_form_component(@client.anon_token).gsub('+', '%20')
        uri.query = "apikey=#{encoded_key}"
        uri.to_s
      end

      def open_socket(address)
        require 'async/http/endpoint'
        require 'async/websocket/client'
        # Use the HTTP/1.1 upgrade supported by the public API.
        endpoint = Async::HTTP::Endpoint.parse(address, protocol: Async::HTTP::Protocol::HTTP11)
        Async::WebSocket::Client.connect(endpoint)
      end

      def realtime_secrets = [@client.anon_token, @client.current_session&.access_token]

      def public_error(error)
        redacted = Redaction.exception(error, secrets: realtime_secrets)
        return redacted unless Transport::NETWORK_ERRORS.any? { |type| error.is_a?(type) }

        transport_error = Error::TransportError.new(redacted.message)
        trace = redacted.backtrace
        transport_error.set_backtrace(trace) if trace
        transport_error
      end
    end
    private_constant :Connection
  end
end
