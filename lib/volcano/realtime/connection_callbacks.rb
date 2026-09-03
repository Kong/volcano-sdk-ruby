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
        emit_connection_events([[event, context]])
      end

      def emit_connection_events(events)
        deliveries = connection_deliveries(events)
        return if deliveries.empty?

        Async::Task.current.async do
          connection_callback_lock.acquire do
            deliveries.each { |event, context, callbacks| dispatch_connection_callbacks(event, context, callbacks) }
          end
        end
        nil
      end

      def connection_deliveries(events)
        events.filter_map do |event, context|
          callbacks = @connection_callbacks.fetch(event).dup
          [event, context, callbacks] unless callbacks.empty?
        end
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
        reset_after_protocol_loss
        emit_connection_event(:disconnect, disconnect_context(error))
        start_reconnect
      end

      def protocol_error(error)
        @protocol_error_reported = true
        emit_connection_event(:error, error_context(error))
      end

      def protocol_error_started(_error)
        @protocol_error_reported = true
      end

      def protocol_failed(error, disconnected)
        reset_after_protocol_loss if disconnected
        events = [[:error, error_context(error)]]
        events << [:disconnect, disconnect_context(error)] if disconnected
        emit_connection_events(events)
        start_reconnect if disconnected
      end

      def error_context(error)
        snapshot = immutable_exception(error)
        ErrorContext.new(
          code: snapshot.respond_to?(:code) ? snapshot.code : nil,
          message: immutable_string(snapshot.message), error: snapshot
        )
      end

      def disconnect_context(error)
        reason = @manual_disconnect ? 'manual' : error.message
        DisconnectContext.new(code: nil, reason: immutable_string(reason))
      end

      def immutable_exception(error)
        snapshot = Redaction.exception(error, secrets: [])
        snapshot.message.freeze
        backtrace = snapshot.backtrace
        snapshot.set_backtrace(backtrace.map { |line| immutable_string(line) }.freeze) if backtrace
        snapshot.freeze
      end

      def immutable_string(value)
        return unless value

        value.to_s.dup.freeze
      end

      def connection_callback_lock
        require 'async/semaphore'
        @connection_callback_lock ||= Async::Semaphore.new(1)
      end

      def reset_after_protocol_loss
        protocol = @protocol
        @protocol = nil
        @protocol_user_id = nil
        @channels.each_value { |channel| channel.protocol_lost(protocol) } if protocol
      end
    end
    private_constant :ConnectionCallbacks
  end
end
