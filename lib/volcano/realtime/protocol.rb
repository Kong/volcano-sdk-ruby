# frozen_string_literal: true

require 'json'
require_relative 'protocol_dispatch'
require_relative 'protocol_lifecycle'

module Volcano
  class Realtime
    # Error returned by the realtime server for a command.
    class ServerError < StandardError
      attr_reader :code

      def initialize(message, code: nil) = super(message).tap { @code = code }
    end

    class ClosedError < StandardError; end
    class DuplicateSubscriptionError < StandardError; end
    class PendingLimitError < StandardError; end
    class RequestTimeoutError < StandardError; end

    # Implements the Centrifuge request and publication protocol.
    class Protocol
      include ProtocolDispatch
      include Lifecycle

      Failure = Data.define(:error)
      Events = Data.define(:on_close, :on_error, :on_failure)
      DEFAULT_REQUEST_TIMEOUT = 10
      DEFAULT_MAX_PENDING = 128
      DEFAULT_MAX_CALLBACK_QUEUE = 128
      LIMIT_KEYS = %i[request_timeout max_pending max_callback_queue].freeze

      def self.connect(id:, token:) = { 'id' => id, 'connect' => { 'token' => token } }

      def self.subscribe(id:, channel:) = { 'id' => id, 'subscribe' => { 'channel' => channel } }

      def self.publish(id:, channel:, data:) = { 'id' => id, 'publish' => { 'channel' => channel, 'data' => data } }

      def self.unsubscribe(id:, channel:) = { 'id' => id, 'unsubscribe' => { 'channel' => channel } }

      def initialize(
        socket:,
        task: nil,
        secrets: [],
        events: nil,
        **limits
      )
        load_async
        @socket = socket
        @secrets = secrets.freeze
        @events = events
        configure_limits(limits)
        initialize_state
        start_tasks(task || Async::Task.current)
      end

      def connect(token:)
        result = request { |id| self.class.connect(id: id, token: token) }
        ensure_open!
        @connected = true
        result
      end

      def subscribe(channel:)
        @subscription_lock.acquire do
          ensure_open!
          raise DuplicateSubscriptionError, "already subscribed to #{channel}" if @subscriptions.include?(channel)

          result = request { |id| self.class.subscribe(id: id, channel: channel) }
          @subscriptions.add(channel)
          result
        end
      end

      def publish(channel:, data:) = request { |id| self.class.publish(id: id, channel: channel, data: data) }

      def unsubscribe(channel:)
        @subscription_lock.acquire do
          ensure_open!
          next {} unless @subscriptions.include?(channel)

          result = request { |id| self.class.unsubscribe(id: id, channel: channel) }
          @subscriptions.delete(channel)
          result
        end
      end

      def close
        return nil if @closed

        close_with(ClosedError.new('realtime connection closed'))
        @reader_task.stop && nil
      end

      private

      def load_async
        require 'async'
        require 'async/queue'
        require 'async/semaphore'
      end

      def configure_limits(limits)
        unknown = limits.keys - LIMIT_KEYS
        raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?

        @request_timeout = limits.fetch(:request_timeout, DEFAULT_REQUEST_TIMEOUT)
        @max_pending = limits.fetch(:max_pending, DEFAULT_MAX_PENDING)
        @max_callback_queue = limits.fetch(:max_callback_queue, DEFAULT_MAX_CALLBACK_QUEUE)
      end

      def initialize_state
        @next_id = 0
        @pending = {}
        @write_lock = Async::Semaphore.new(1)
        @subscription_lock = Async::Semaphore.new(1)
        @publication_handlers = Hash.new { |hash, key| hash[key] = [] }
        @callback_queue = Async::Queue.new
        @callback_stopping = @connected = @closed = false
        @subscriptions = Set.new
        @closed_error = nil
      end

      def start_tasks(task)
        @callback_task = task.async { dispatch_callbacks }
        @reader_task = task.async { read_loop }
      end

      def ensure_open!
        raise @closed_error if @closed

        self
      end

      def reject_pending(error) = @pending.each_value { |queue| queue.enqueue(Failure.new(error: error)) }

      def close_socket
        @socket.close
      rescue StandardError
        nil
      end

      def stop_callback_task
        @callback_stopping = true
        @callback_task.stop unless @callback_task == Async::Task.current
      end
    end
  end
end

require_relative 'protocol_io'
