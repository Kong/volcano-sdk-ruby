# frozen_string_literal: true

module Volcano
  class Realtime
    # Collects compatible row lookups and preserves their callback order.
    module PostgresBatch
      BATCH_LIMIT = 50
      BATCH_WINDOW = 0.02
      private_constant :BATCH_LIMIT, :BATCH_WINDOW

      private

      def collect_postgres_batch(first)
        return [[first], nil] unless first.database_name

        deadline = monotonic_time + BATCH_WINDOW
        requests = [first]
        pending = collect_compatible_requests(requests, deadline)
        [requests, pending]
      end

      def collect_compatible_requests(requests, deadline)
        while requests.length < BATCH_LIMIT
          request = dequeue_postgres_before(deadline)
          return unless request
          return request unless compatible_postgres_request?(requests.first, request)

          requests << request
        end
        nil
      end

      def dequeue_postgres_before(deadline)
        remaining = deadline - monotonic_time
        return unless remaining.positive?

        Async::Task.current.with_timeout(remaining) { @postgres_queue.dequeue }
      rescue Async::TimeoutError
        nil
      end

      def compatible_postgres_request?(first, candidate)
        !postgres_stop?(candidate) && candidate.database_name &&
          postgres_batch_key(first) == postgres_batch_key(candidate)
      end

      def postgres_batch_key(request)
        change = request.change
        [
          request.database_name, request.session_lineage, request.subscription_epoch,
          change.schema, change.table
        ]
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def deliver_postgres_batch(requests)
        return unless current_postgres_request?(requests.first)

        changes = expanded_postgres_changes(requests)
        requests.zip(changes).each do |request, change|
          deliver_expanded_postgres_change(request, change)
        end
      end

      def deliver_expanded_postgres_change(request, change)
        return unless current_postgres_request?(request)

        emit(change.type, change)
        emit('*', change) if current_postgres_request?(request)
      end
    end
    private_constant :PostgresBatch
  end
end
