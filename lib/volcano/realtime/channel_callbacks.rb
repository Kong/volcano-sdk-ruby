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
        @publication_generation = 0
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

        generation = @publication_generation
        @publication_handler = protocol.on_publication(@name) do |event, data, publication, recovered:|
          next deliver_publication(event, data) unless broadcast?

          context = PublicationContext.new(protocol:, publication:, generation:, recovered:)
          deliver_broadcast(event, data, context)
        end
        @handler_registered = true
      end

      def deliver_broadcast(event, data, context)
        return context.protocol.drop_publication(@name, context.publication) unless
          event == 'message' && @callbacks['message'].any?

        emit('message', data, before_delivery: -> { complete_broadcast_publication(context) })
      end

      def complete_broadcast_publication(context)
        admitted = false
        with_lifecycle_lock do
          next false unless context.generation == @publication_generation

          context.protocol.complete_publication(@name, context.publication)
          @stream_position = context.protocol.position(@name) || @stream_position
          admitted = true
        end
      ensure
        context.protocol.drop_publication(@name, context.publication) unless admitted
      end

      def deliver_publication(event, data)
        if postgres?
          dispatch_postgres_change(data)
        elsif event == 'message'
          emit('message', data)
        end
      end

      def emit(event, data, before_delivery: nil)
        callbacks = @callbacks[event].dup
        return if callbacks.empty?

        delivery = [event, data, callbacks, before_delivery]
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
        event, data, callbacks, before_delivery = @deferred_callback_deliveries.shift
        return if before_delivery && !before_delivery.call

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
        if @publication_handler
          protocol.off_publication(@name, @publication_handler)
          @publication_generation += 1 if broadcast?
        end
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
