# frozen_string_literal: true

module Volcano
  class Realtime
    # Normalizes publications and admits live deliveries without blocking the reader.
    module ProtocolPublicationDispatch
      Registration = Data.define(:handler, :on_rejection)
      PublicationDelivery = Data.define(
        :channel, :handlers, :event, :data, :publication, :recovered, :on_rejection
      )
      private_constant :PublicationDelivery

      private

      def dispatch_publication(push)
        channel = push['channel'].to_s
        publication = push['pub']
        delivery = publication_delivery(channel, publication, recovered: false)
        return unless delivery

        enqueue_live_publication(delivery)
      end

      def publication_delivery(channel, publication, recovered:)
        matched_channel = matching_publication_channel(channel)
        return unless matched_channel
        return reject_invalid_publication(matched_channel, publication) unless valid_publication?(publication)
        unless @publication_handlers.key?(matched_channel)
          return drop_handlerless_publication(matched_channel, publication)
        end

        build_publication_delivery(matched_channel, publication, recovered: recovered)
      end

      def matching_publication_channel(channel)
        handler_channel = matching_channel(@publication_handlers, channel)
        recovery_channel = matching_channel(@stream_positions, channel)
        [handler_channel, recovery_channel].compact.max_by(&:length)
      end

      def valid_publication?(publication)
        publication.is_a?(Hash) && publication['data'].is_a?(Hash)
      end

      def reject_invalid_publication(channel, publication)
        return unless channel

        if publication.is_a?(Hash)
          drop_publication(channel, publication)
        else
          mark_unknown_gap(channel)
        end
        nil
      end

      def drop_handlerless_publication(channel, publication)
        drop_publication(channel, publication) if channel
        nil
      end

      def build_publication_delivery(channel, publication, recovered:)
        registrations = @publication_handlers.fetch(channel).dup.freeze
        data = publication.fetch('data')
        PublicationDelivery.new(
          channel: channel.dup.freeze,
          handlers: registrations.map(&:handler).freeze,
          event: data['event'],
          data: data,
          publication: publication,
          recovered: recovered,
          on_rejection: combined_rejection_hook(registrations)
        )
      end

      def combined_rejection_hook(registrations)
        hooks = registrations.filter_map(&:on_rejection).freeze
        return if hooks.empty?
        return hooks.first if hooks.one?

        ->(publication) { hooks.each { |hook| hook.call(publication) } }
      end

      def admit_live_publication(delivery)
        return reject_publication_delivery(delivery) if callback_queue_full?

        @callback_queue.enqueue(delivery)
      end

      def callback_queue_full? = @callback_queue.limited?

      def reject_publication_delivery(delivery)
        if delivery.on_rejection
          delivery.on_rejection.call(delivery.publication)
        else
          drop_publication(delivery.channel, delivery.publication)
        end
      end

      def dispatch_queued_callback(delivery)
        if delivery.is_a?(PublicationDelivery)
          dispatch_publication_callbacks(delivery)
        else
          dispatch_callback_delivery(*delivery)
        end
      end

      def dispatch_publication_callbacks(delivery)
        delivery.handlers.each do |handler|
          break if @callback_stopping

          handler.call(
            delivery.event, delivery.data, delivery.publication, recovered: delivery.recovered
          )
        rescue StandardError
          next
        end
      end
    end
  end
end
