# frozen_string_literal: true

module Volcano
  class Realtime
    PostgresDeliveryRequest = Data.define(
      :change, :database_name, :session_lineage, :subscription_epoch, :protocol, :publication
    )
    private_constant :PostgresDeliveryRequest

    # Serializes Postgres publications and expands lightweight row identities.
    module PostgresDelivery
      QUEUE_LIMIT = 128
      STOP = Object.new.freeze
      private_constant :QUEUE_LIMIT, :STOP

      private

      def initialize_postgres_delivery(batch_config)
        require 'async/queue'
        @postgres_batch_config = batch_config
        @postgres_filters = {}
        @postgres_queue = Async::LimitedQueue.new(QUEUE_LIMIT)
        @postgres_worker = nil
        @postgres_epoch = 0
        @postgres_session_lineage = 0
      end

      def ensure_fetch_config!(batch_config)
        return if @postgres_batch_config == batch_config
        if @postgres_batch_config.auto_fetch != batch_config.auto_fetch
          raise ArgumentError, "conflicting auto_fetch option for #{@name}"
        end

        raise ArgumentError, "conflicting fetch options for #{@name}"
      end

      def begin_postgres_delivery
        return unless postgres?

        @postgres_epoch += 1
        _, lineage, = @realtime.__send__(:capture_protocol_session)
        @postgres_session_lineage = lineage
      end

      def end_postgres_delivery
        return unless postgres?

        @postgres_epoch += 1
        @postgres_queue.dequeue until @postgres_queue.empty?
        worker = @postgres_worker
        return unless worker

        @postgres_queue.enqueue(STOP)
        @postgres_worker = nil
        worker.wait unless worker.equal?(Async::Task.current)
      end

      def enqueue_postgres_delivery(change, protocol = nil, publication = nil)
        return :rejected unless @subscribed

        request = postgres_delivery_request(change, protocol, publication)
        if @postgres_queue.limited?
          report_postgres_queue_overflow
          return :rejected
        end

        start_postgres_worker
        @postgres_queue.enqueue(request)
        :queued
      end

      def postgres_delivery_request(change, protocol, publication)
        database_name = @realtime.__send__(:database_name)
        fetch = fetch_postgres_change?(change, database_name)
        PostgresDeliveryRequest.new(
          change:, database_name: fetch ? database_name : nil,
          session_lineage: @postgres_session_lineage,
          subscription_epoch: @postgres_epoch, protocol:, publication:
        )
      end

      def fetch_postgres_change?(change, database_name)
        change.mode == 'lightweight' && change.type != 'DELETE' &&
          @postgres_batch_config.auto_fetch && database_name
      end

      def report_postgres_queue_overflow
        error = PendingLimitError.new("realtime Postgres delivery queue limit #{QUEUE_LIMIT} reached")
        @realtime.__send__(:report_channel_error, error)
      end

      def start_postgres_worker
        return if @postgres_worker

        @postgres_worker = Async::Task.current.async { run_postgres_worker }
      end

      def run_postgres_worker
        pending = nil
        loop do
          request = pending || @postgres_queue.dequeue
          break if postgres_stop?(request)

          requests, pending = collect_postgres_batch(request)
          deliver_postgres_batch(requests)
        end
      ensure
        @postgres_worker = nil if @postgres_worker.equal?(Async::Task.current)
      end

      def postgres_stop?(request) = request.equal?(STOP)

      def current_postgres_request?(request)
        _, lineage, = @realtime.__send__(:capture_session_binding)
        @subscribed && request.subscription_epoch == @postgres_epoch &&
          request.session_lineage == lineage
      end
    end
    private_constant :PostgresDelivery
  end
end
