# frozen_string_literal: true

module Volcano
  class Realtime
    PublicationContext = Data.define(:protocol, :publication, :generation, :recovered)
    private_constant :PublicationContext

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

        generation = @publication_generation += 1
        @publication_handler = protocol.on_publication(@name) do |event, data, publication, recovered:|
          next unless generation == @publication_generation

          context = PublicationContext.new(protocol:, publication:, generation:, recovered:)
          deliver_publication(event, data, context)
        end
        @handler_registered = true
      end

      def complete_publication_delivery(context)
        return false unless context&.protocol && context.publication

        with_lifecycle_lock do
          next false unless context.generation == @publication_generation

          position = context.protocol.complete_publication(@name, context.publication)
          @stream_position = position if position
          true
        end
      end

      def deliver_publication(event, data, context)
        if postgres?
          dispatch_postgres_change(data, context)
        else
          deliver_message(event, data, context)
        end
      end

      def deliver_message(event, data, context)
        return complete_publication_delivery(context) unless event == 'message'

        completion = -> { complete_publication_delivery(context) }
        emit('message', data, before_delivery: completion)
      end

      def emit(event, data, before_delivery: nil)
        callbacks = @callbacks[event].dup
        return if callbacks.empty? && !before_delivery

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
        protocol.off_publication(@name, @publication_handler) if @publication_handler
        detach_presence_handler(protocol)
        @publication_generation += 1
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
