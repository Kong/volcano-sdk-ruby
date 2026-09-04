# frozen_string_literal: true

module Volcano
  class Realtime
    # Delivers broadcasts only while their subscription generation is current.
    module BroadcastDelivery
      PublicationContext = Data.define(:protocol, :publication, :generation, :recovered) do
        def initialize(protocol:, publication:, generation:, recovered:)
          super(protocol:, publication: Immutable.call(publication), generation:, recovered:)
        end
      end
      private_constant :PublicationContext

      private

      def deliver_broadcast(event, data, context)
        return reject_broadcast(context) unless broadcast_message?(event, data)

        emit(
          'message', Immutable.call(data),
          before_delivery: -> { complete_broadcast(context) }
        )
      end

      def broadcast_message?(event, data)
        event == 'message' && data.is_a?(Hash) && @callbacks['message'].any?
      end

      def publication_context(protocol, publication, generation, recovered)
        PublicationContext.new(protocol:, publication:, generation:, recovered:)
      end

      def reject_broadcast(context)
        with_current_publication(context) do
          context.protocol.__send__(:drop_publication, @name, context.publication)
        end
      end

      def complete_broadcast(context)
        with_current_publication(context) do
          context.protocol.__send__(:complete_publication, @name, context.publication)
        end
      end

      def with_current_publication(context)
        with_lifecycle_lock do
          next false unless context.generation == @publication_generation

          yield
          true
        end
      end

      def clear_broadcast_recovery_state
        return unless broadcast? && @publication_protocol

        @publication_protocol.__send__(:delete_recovery_state, @name)
        @publication_protocol = nil
      end
    end
    private_constant :BroadcastDelivery
  end
end
