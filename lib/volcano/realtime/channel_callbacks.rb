# frozen_string_literal: true

module Volcano
  class Realtime
    # Registers channel callbacks and connects them to protocol pushes.
    module ChannelCallbacks
      def on(event, callback = nil, &block)
        raise ArgumentError, "unsupported realtime event: #{event}" unless allowed_event?(event)

        @callbacks[event] << (callback || block || raise(ArgumentError, 'callback or block is required'))
        self
      end

      private

      def initialize_callback_dispatch
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @publication_handler = @callback_lock = @callback_task = nil
        @deferred_callback_deliveries = []
      end

      def allowed_event?(event)
        event == 'message' || (presence? && %w[join leave presence_sync].include?(event)) ||
          (postgres? && PostgresChanges::EVENTS.include?(event))
      end

      def register_handlers(protocol, epoch)
        register_publication_handler(protocol)
        register_presence_handler(protocol, epoch)
      end

      def register_publication_handler(protocol)
        return if @handler_registered

        @publication_handler = protocol.on_publication(@name) { |event, data| deliver_publication(event, data) }
        @handler_registered = true
      end

      def deliver_publication(event, data)
        if postgres?
          dispatch_postgres_change(data)
        elsif event == 'message'
          emit('message', data)
        end
      end

      def emit(event, data)
        callbacks = @callbacks[event].dup
        return if callbacks.empty?

        delivery = [event, data, callbacks]
        return defer_callback_delivery(delivery) if callback_dispatching?

        callback_lock.acquire { dispatch_callback_delivery(delivery) }
        nil
      end

      def callback_dispatching?
        @callback_task.equal?(Async::Task.current)
      end

      def defer_callback_delivery(delivery)
        @deferred_callback_deliveries << delivery
        nil
      end

      def dispatch_callback_delivery(delivery)
        @callback_task = Async::Task.current
        @deferred_callback_deliveries << delivery
        dispatch_deferred_callbacks until @deferred_callback_deliveries.empty?
      ensure
        @callback_task = nil
      end

      def dispatch_deferred_callbacks
        event, data, callbacks = @deferred_callback_deliveries.shift
        dispatch_callbacks(event, data, callbacks)
      end

      def dispatch_callbacks(event, data, callbacks)
        callbacks.each do |callback|
          next unless @callbacks[event].include?(callback)

          callback.call(data)
        rescue StandardError
          next
        end
      end

      def detach_publication_handler(protocol)
        protocol.off_publication(@name, @publication_handler) if @publication_handler
        detach_presence_handler(protocol)
        @publication_handler = nil
      end

      def callback_lock
        require 'async/semaphore'
        @callback_lock ||= Async::Semaphore.new(1)
      end
    end
    private_constant :ChannelCallbacks
  end
end
