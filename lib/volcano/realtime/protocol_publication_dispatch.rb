# frozen_string_literal: true

module Volcano
  class Realtime
    # Prepares publications and admits them to callback delivery.
    module ProtocolPublicationDispatch
      PublicationDelivery = Data.define(:channel, :handlers, :event, :data, :publication, :recovered)
      private_constant :PublicationDelivery

      private

      def dispatch_publication(push, recovered: false, enforce_limit: true)
        delivery = publication_delivery(push, recovered)
        return unless delivery

        if !recovered && ordered_publication_channel?(delivery.channel)
          enqueue_ordered_publication(delivery)
        else
          admit_publication(delivery, enforce_limit:)
        end
      end

      def publication_delivery(push, recovered)
        publication = push['pub']
        data = publication.is_a?(Hash) ? publication['data'] : nil
        return unless data.is_a?(Hash)

        channel = matching_channel(@publication_handlers, push['channel'].to_s)
        return unless channel

        PublicationDelivery.new(
          channel:, handlers: @publication_handlers.fetch(channel).dup,
          event: data['event'], data:, publication:, recovered:
        )
      end

      def admit_publication(delivery, enforce_limit:)
        if enforce_limit && @callback_queue.limited?
          drop_publication(delivery.channel, delivery.publication)
          return
        end

        @callback_queue.enqueue(
          [
            delivery.handlers, delivery.event, delivery.data,
            delivery.publication, delivery.recovered
          ]
        )
      end
    end
  end
end
