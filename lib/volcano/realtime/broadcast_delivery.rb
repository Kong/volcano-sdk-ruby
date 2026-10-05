# frozen_string_literal: true

module Volcano
  class Realtime
    # Delivers broadcasts only while their subscription generation is current.
    module BroadcastDelivery
      # @dynamic emit, with_lifecycle_lock, broadcast?
      # Captures the subscription generation alongside an immutable publication.
      PublicationContext = Data.define(:protocol, :publication, :generation, :recovered)

      # Freezes the publication before callbacks can observe or modify it.
      class PublicationContext
        # @dynamic protocol, publication, generation, recovered
        def initialize(protocol:, publication:, generation:, recovered:)
          publication = Immutable.call(publication)
          super
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

      def publication_rejection(protocol, generation)
        return unless broadcast?

        lambda do |publication|
          reject_broadcast(publication_context(protocol, publication, generation, false))
        end
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

      def clear_channel_recovery_state
        return unless broadcast?

        # @type var position: Hash[Symbol, String | Integer]
        position = {}
        @recovery_position = position.freeze
        @recovery_lineage = nil
      end
    end
    private_constant :BroadcastDelivery
  end
end
