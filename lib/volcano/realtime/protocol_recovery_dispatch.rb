# frozen_string_literal: true

module Volcano
  class Realtime
    # Preserves publication order while recovered deliveries wait for callback capacity.
    module ProtocolRecoveryDispatch
      PublicationBatch = Data.define(:channel, :deliveries, :rejection_key)
      private_constant :PublicationBatch

      private

      def initialize_publication_producer
        @publication_queue = Async::Queue.new
        @publication_queue_size = 0
        @publication_pending_by_channel = Hash.new(0)
        @publication_rejections = {}
        @producer_stopping = false
      end

      def dispatch_recovered_publications(channel, publications)
        deliveries = publications.filter_map do |publication|
          publication_delivery(channel, publication, recovered: true)
        end
        return if deliveries.empty?

        enqueue_recovered_batch(publication_batch(channel, deliveries))
      end

      def publication_batch(channel, deliveries, rejection_key: nil)
        PublicationBatch.new(
          channel: channel.dup.freeze, deliveries: deliveries.freeze, rejection_key: rejection_key
        )
      end

      def enqueue_recovered_batch(batch)
        if publication_queue_full?
          batch.deliveries.each { |delivery| enqueue_publication_rejection(delivery) }
          raise PendingLimitError, "realtime publication producer limit #{@max_callback_queue} reached"
        end

        enqueue_publication_batch(batch)
      end

      def enqueue_live_publication(delivery)
        return enqueue_publication_rejection(delivery) if publication_queue_full?

        enqueue_publication_batch(publication_batch(delivery.channel, [delivery]))
      end

      def enqueue_publication_rejection(delivery)
        key = [delivery.channel, delivery.rejection_key].freeze
        return if @publication_rejections.key?(key)

        @publication_rejections[key] = true
        enqueue_publication_batch(
          publication_batch(delivery.channel, [delivery], rejection_key: key), bounded: false
        )
      end

      def enqueue_publication_batch(batch, bounded: true)
        @publication_queue_size += 1 if bounded
        @publication_pending_by_channel[batch.channel] += 1
        @publication_queue.enqueue(batch)
      end

      def publication_queue_full? = @publication_queue_size >= @max_callback_queue

      def dispatch_publication_batches
        until @producer_stopping
          batch = next_publication_batch
          begin
            dispatch_publication_batch(batch)
          ensure
            complete_publication_batch(batch)
          end
        end
      rescue StandardError => e
        close_with(closed_error(e), notify_error: true)
      end

      def next_publication_batch
        batch = @publication_queue.dequeue
        @publication_queue_size -= 1 unless batch.rejection_key
        batch
      end

      def dispatch_publication_batch(batch)
        return batch.deliveries.each { |delivery| reject_publication_delivery(delivery) } if batch.rejection_key

        batch.deliveries.each do |delivery|
          if delivery.recovered
            @callback_queue.enqueue(delivery)
          else
            admit_live_publication(delivery)
          end
        end
      end

      def complete_publication_batch(batch)
        @publication_rejections.delete(batch.rejection_key) if batch.rejection_key
        @publication_pending_by_channel[batch.channel] -= 1
        @publication_pending_by_channel.delete(batch.channel) if @publication_pending_by_channel[batch.channel].zero?
      end
    end
  end
end
