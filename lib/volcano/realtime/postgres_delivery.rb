# frozen_string_literal: true

module Volcano
  class Realtime
    PostgresDeliveryRequest = Data.define(
      :change, :database_name, :access_token, :session_generation, :subscription_epoch
    )
    private_constant :PostgresDeliveryRequest

    # Serializes Postgres publications and expands lightweight row identities.
    module PostgresDelivery
      QUEUE_LIMIT = 128
      STOP = Object.new.freeze
      private_constant :QUEUE_LIMIT, :STOP

      private

      def initialize_postgres_delivery(auto_fetch)
        require 'async/queue'
        @auto_fetch = auto_fetch
        @postgres_filters = {}
        @postgres_queue = Async::LimitedQueue.new(QUEUE_LIMIT)
        @postgres_worker = nil
        @postgres_epoch = 0
        @postgres_session_generation = 0
        @postgres_access_token = @postgres_user_id = nil
      end

      def ensure_auto_fetch!(auto_fetch)
        return if @auto_fetch == auto_fetch

        raise ArgumentError, "conflicting auto_fetch option for #{@name}"
      end

      def begin_postgres_delivery
        return unless postgres?

        @postgres_epoch += 1
        generation, session = @realtime.__send__(:capture_session)
        @postgres_session_generation = generation
        @postgres_access_token = session&.access_token
        @postgres_user_id = session&.user_id
      end

      def end_postgres_delivery
        return unless postgres?

        @postgres_epoch += 1
        @postgres_access_token = @postgres_user_id = nil
        @postgres_queue.dequeue until @postgres_queue.empty?
        worker = @postgres_worker
        return unless worker

        @postgres_queue.enqueue(STOP)
        @postgres_worker = nil
        worker.wait unless worker.equal?(Async::Task.current)
      end

      def enqueue_postgres_delivery(change)
        return unless @subscribed

        refresh_postgres_session_binding
        fetch = fetch_postgres_change?(change)
        start_postgres_worker
        @postgres_queue.enqueue(
          PostgresDeliveryRequest.new(
            change:, database_name: fetch ? @realtime.__send__(:database_name) : nil,
            access_token: fetch ? @postgres_access_token : nil,
            session_generation: @postgres_session_generation,
            subscription_epoch: @postgres_epoch
          )
        )
      end

      def refresh_postgres_session_binding
        generation, session = @realtime.__send__(:capture_session)
        return if generation == @postgres_session_generation
        return unless session&.user_id == @postgres_user_id

        @postgres_session_generation = generation
        @postgres_access_token = session.access_token
      end

      def fetch_postgres_change?(change)
        change.mode == 'lightweight' && change.type != 'DELETE' && @auto_fetch &&
          @realtime.__send__(:database_name) && @postgres_access_token
      end

      def start_postgres_worker
        return if @postgres_worker

        @postgres_worker = Async::Task.current.async { run_postgres_worker }
      end

      def run_postgres_worker
        loop do
          request = @postgres_queue.dequeue
          break if request.equal?(STOP)

          deliver_postgres_change(request)
        end
      ensure
        @postgres_worker = nil if @postgres_worker.equal?(Async::Task.current)
      end

      def deliver_postgres_change(request)
        return unless current_postgres_request?(request)

        change = expanded_postgres_change(request)
        return unless current_postgres_request?(request)

        emit(change.type, change)
        emit('*', change) if current_postgres_request?(request)
      end

      def current_postgres_request?(request)
        generation, = @realtime.__send__(:capture_session)
        @subscribed && request.subscription_epoch == @postgres_epoch &&
          request.session_generation == generation
      end
    end
    private_constant :PostgresDelivery
  end
end
