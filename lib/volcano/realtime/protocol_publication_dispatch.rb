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
        channel = matching_publication_channel(push['channel'].to_s)
        return unless channel

        data = validated_publication_data(channel, publication)
        handlers = registered_publication_handlers(channel, publication)
        return unless data && handlers

        PublicationDelivery.new(
          channel:, handlers: handlers.dup,
          event: data['event'], data:, publication:, recovered:
        )
      end

      def matching_publication_channel(channel)
        handler_channel = matching_channel(@publication_handlers, channel)
        position_channel = matching_channel(@stream_positions, channel)
        [handler_channel, position_channel].compact.max_by(&:length)
      end

      def validated_publication_data(channel, publication)
        data = publication.is_a?(Hash) ? publication['data'] : nil
        return data if data.is_a?(Hash)

        drop_publication(channel, publication)
      end

      def registered_publication_handlers(channel, publication)
        handlers = @publication_handlers.fetch(channel, [])
        return handlers unless handlers.empty?

        drop_publication(channel, publication)
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
