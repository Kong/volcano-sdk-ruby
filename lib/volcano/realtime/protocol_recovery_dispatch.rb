# frozen_string_literal: true

module Volcano
  class Realtime
    # Admits retained publications on a bounded producer task in frame order.
    module ProtocolRecoveryDispatch
      PublicationBatch = Data.define(:channel, :deliveries)
      private_constant :PublicationBatch

      private

      def enqueue_recovered_publications(channel, publications)
        deliveries = publications.filter_map do |publication|
          publication_delivery({ 'channel' => channel, 'pub' => publication }, true)
        end
        return if deliveries.empty?
        return if publication_batch_enqueued?(channel, deliveries)

        deliveries.each { |delivery| drop_publication(channel, delivery.publication) }
      end

      def enqueue_ordered_publication(delivery)
        return if publication_batch_enqueued?(delivery.channel, [delivery])

        drop_publication(delivery.channel, delivery.publication)
      end

      def publication_batch_enqueued?(channel, deliveries)
        return false if @ordered_publication_queue.limited?

        @ordered_publication_counts[channel] += 1
        @ordered_publication_queue.enqueue(
          PublicationBatch.new(channel:, deliveries: deliveries.freeze)
        )
        true
      end

      def ordered_publication_channel?(channel) = @ordered_publication_counts[channel].positive?

      def dispatch_ordered_publications
        until @publication_producer_stopping
          batch = @ordered_publication_queue.dequeue
          dispatch_publication_batch(batch)
        end
      rescue StandardError => e
        close_with(closed_error(e), notify_error: true) unless @publication_producer_stopping
      end

      def dispatch_publication_batch(batch)
        batch.deliveries.each do |delivery|
          admit_publication(delivery, enforce_limit: !delivery.recovered)
        end
      ensure
        remaining = @ordered_publication_counts.fetch(batch.channel) - 1
        if remaining.positive?
          @ordered_publication_counts[batch.channel] = remaining
        else
          @ordered_publication_counts.delete(batch.channel)
        end
      end

      def initialize_ordered_publication_dispatch
        @ordered_publication_queue = Async::LimitedQueue.new(@max_callback_queue)
        @ordered_publication_counts = Hash.new(0)
        @publication_producer_stopping = false
      end
    end
  end
end
