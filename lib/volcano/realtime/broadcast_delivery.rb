# frozen_string_literal: true

module Volcano
  class Realtime
    # Delivers broadcasts only while their subscription generation is current.
    module BroadcastDelivery
      private

      def deliver_broadcast(event, data, context)
        return drop_broadcast_publication(context) unless
          event == 'message' && @callbacks['message'].any?

        emit('message', data, before_delivery: -> { complete_broadcast_publication(context) })
      end

      def drop_broadcast_publication(context)
        with_lifecycle_lock do
          next false unless context.generation == @publication_generation

          context.protocol.drop_publication(@name, context.publication)
          true
        end
      end

      def complete_broadcast_publication(context)
        outcome = with_lifecycle_lock { complete_current_broadcast_publication(context) }
        outcome == :completed
      ensure
        context.protocol.drop_publication(@name, context.publication) unless outcome
      end

      def complete_current_broadcast_publication(context)
        return :superseded unless context.generation == @publication_generation

        context.protocol.complete_publication(@name, context.publication)
        @stream_position = context.protocol.position(@name) || @stream_position
        :completed
      end
    end
    private_constant :BroadcastDelivery
  end
end
