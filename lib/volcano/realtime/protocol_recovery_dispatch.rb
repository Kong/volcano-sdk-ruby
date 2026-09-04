# frozen_string_literal: true

module Volcano
  class Realtime
    # Preserves publication order while recovered deliveries wait for callback capacity.
    module ProtocolRecoveryDispatch
      PublicationBatch = Data.define(:channel, :deliveries)
      private_constant :PublicationBatch

      private

      def initialize_publication_producer
        @publication_queue = Async::LimitedQueue.new(@max_callback_queue)
        @publication_pending = 0
        @publication_pending_by_channel = Hash.new(0)
        @producer_stopping = false
      end

      def dispatch_recovered_publications(channel, publications)
        deliveries = publications.filter_map do |publication|
          publication_delivery(channel, publication, recovered: true)
        end
        return if deliveries.empty?

        enqueue_recovered_batch(publication_batch(channel, deliveries))
      end

      def publication_batch(channel, deliveries)
        PublicationBatch.new(channel: channel.dup.freeze, deliveries: deliveries.freeze)
      end

      def enqueue_recovered_batch(batch)
        if publication_queue_full?
          batch.deliveries.each { |delivery| reject_publication_delivery(delivery) }
          raise PendingLimitError, "realtime publication producer limit #{@max_callback_queue} reached"
        end

        enqueue_publication_batch(batch)
      end

      def enqueue_live_publication(delivery)
        return reject_publication_delivery(delivery) if publication_queue_full?

        enqueue_publication_batch(publication_batch(delivery.channel, [delivery]))
      end

      def enqueue_publication_batch(batch)
        @publication_pending += 1
        @publication_pending_by_channel[batch.channel] += 1
        @publication_queue.enqueue(batch)
      end

      def publication_queue_full? = @publication_queue.limited?

      def publication_ordered? = @publication_pending.positive?

      def dispatch_publication_batches
        until @producer_stopping
          batch = @publication_queue.dequeue
          begin
            dispatch_publication_batch(batch)
          ensure
            complete_publication_batch(batch)
          end
        end
      rescue StandardError => e
        close_with(closed_error(e), notify_error: true)
      end

      def dispatch_publication_batch(batch)
        batch.deliveries.each do |delivery|
          if delivery.recovered
            @callback_queue.enqueue(delivery)
          else
            admit_live_publication(delivery)
          end
        end
      end

      def complete_publication_batch(batch)
        @publication_pending -= 1
        @publication_pending_by_channel[batch.channel] -= 1
        @publication_pending_by_channel.delete(batch.channel) if @publication_pending_by_channel[batch.channel].zero?
      end
    end
  end
end
