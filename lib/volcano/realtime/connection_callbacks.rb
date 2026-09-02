# frozen_string_literal: true

module Volcano
  class Realtime
    # Registers and dispatches public connection lifecycle callbacks.
    module ConnectionCallbacks
      def on_connect(callback = nil, &block) = register_connection_callback(:connect, callback, block)
      def on_disconnect(callback = nil, &block) = register_connection_callback(:disconnect, callback, block)
      def on_error(callback = nil, &block) = register_connection_callback(:error, callback, block)

      private

      def register_connection_callback(event, callback, block)
        handler = callback || block
        raise ArgumentError, 'callback or block is required' unless handler
        raise ArgumentError, 'callback must respond to call' unless handler.respond_to?(:call)

        @next_connection_callback_id += 1
        callback_id = @next_connection_callback_id
        @connection_callbacks.fetch(event)[callback_id] = handler
        -> { @connection_callbacks.fetch(event).delete(callback_id) }
      end

      def emit_connection_event(event, context)
        callbacks = @connection_callbacks.fetch(event).dup
        return if callbacks.empty?

        Async::Task.current.async do
          connection_callback_lock.acquire { dispatch_connection_callbacks(event, context, callbacks) }
        end
        nil
      end

      def dispatch_connection_callbacks(event, context, callbacks)
        callbacks.each do |callback_id, callback|
          next unless @connection_callbacks.fetch(event)[callback_id].equal?(callback)

          callback.call(context)
        rescue StandardError
          next
        end
      end

      def protocol_connected(result)
        client = result['client']
        emit_connection_event(:connect, ConnectContext.new(client: immutable_string(client)))
      end

      def protocol_closed(error)
        reason = @manual_disconnect ? 'manual' : error.message
        context = DisconnectContext.new(code: nil, reason: immutable_string(reason))
        emit_connection_event(:disconnect, context)
      end

      def protocol_error(error)
        @reported_protocol_error = error
        snapshot = Redaction.exception(error, secrets: []).freeze
        context = ErrorContext.new(
          code: nil,
          message: immutable_string(snapshot.message),
          error: snapshot
        )
        emit_connection_event(:error, context)
      end

      def immutable_string(value)
        return unless value

        value.to_s.dup.freeze
      end

      def connection_callback_lock
        require 'async/semaphore'
        @connection_callback_lock ||= Async::Semaphore.new(1)
      end
    end
    private_constant :ConnectionCallbacks
  end
end
