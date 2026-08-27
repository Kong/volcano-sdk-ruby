# frozen_string_literal: true

require 'json'
require_relative 'protocol_dispatch'

module Volcano
  class Realtime
    class ServerError < StandardError
      attr_reader :code

      def initialize(message, code: nil) = super(message).tap { @code = code }
    end

    class ClosedError < StandardError; end
    class DuplicateSubscriptionError < StandardError; end
    class PendingLimitError < StandardError; end
    class RequestTimeoutError < StandardError; end

    class Protocol
      include ProtocolDispatch

      Failure = Data.define(:error)
      DEFAULT_REQUEST_TIMEOUT = 10
      DEFAULT_MAX_PENDING = 128
      DEFAULT_MAX_CALLBACK_QUEUE = 128

      def self.connect(id:, token:) = { 'id' => id, 'connect' => { 'token' => token } }

      def self.subscribe(id:, channel:) = { 'id' => id, 'subscribe' => { 'channel' => channel } }

      def self.publish(id:, channel:, data:) = { 'id' => id, 'publish' => { 'channel' => channel, 'data' => data } }

      def self.unsubscribe(id:, channel:) = { 'id' => id, 'unsubscribe' => { 'channel' => channel } }

      def initialize(
        socket:,
        task: nil,
        secrets: [],
        request_timeout: DEFAULT_REQUEST_TIMEOUT,
        max_pending: DEFAULT_MAX_PENDING,
        max_callback_queue: DEFAULT_MAX_CALLBACK_QUEUE
      )
        require 'async'
        require 'async/queue'
        require 'async/semaphore'
        task ||= Async::Task.current
        @socket = socket
        @secrets = secrets.freeze
        @request_timeout = request_timeout
        @max_pending = max_pending
        @next_id = 0
        @pending = {}
        @write_lock = Async::Semaphore.new(1)
        @subscription_lock = Async::Semaphore.new(1)
        @publication_handlers = Hash.new { |hash, key| hash[key] = [] }
        @callback_queue = Async::Queue.new
        @max_callback_queue = max_callback_queue
        @callback_stopping = @closed = false
        @subscriptions = Set.new
        @closed_error = nil
        @callback_task = task.async { dispatch_callbacks }
        @reader_task = task.async { read_loop }
      end

      def connect(token:) = request { |id| self.class.connect(id: id, token: token) }

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

      def on_publication(channel, &block) = ensure_open!.tap { @publication_handlers[channel] << block }

      def close
        close_with(ClosedError.new('realtime connection closed'))
        @reader_task.stop && nil
      end

      private

      def request
        ensure_open!
        if @pending.length >= @max_pending
          raise PendingLimitError, "realtime pending command limit #{@max_pending} reached"
        end

        @next_id += 1
        id = @next_id
        reply_queue = Async::Queue.new
        @pending[id] = reply_queue
        write_frame(yield(id))
        reply = Async::Task.current.with_timeout(
          @request_timeout,
          RequestTimeoutError,
          "realtime command timed out after #{@request_timeout} seconds"
        ) { reply_queue.dequeue }
        raise reply.error if reply.is_a?(Failure)

        reply
      rescue StandardError => e
        raise Redaction.exception(e, secrets: @secrets), cause: nil
      ensure
        @pending.delete(id) if defined?(id)
      end

      def read_loop
        loop do
          Async::Task.current.yield
          message = @socket.read
          break unless message

          message.to_str.each_line do |line|
            next if line.strip.empty?

            process(JSON.parse(line))
          end
        end
      rescue JSON::ParserError => e
        message = Redaction.message("invalid realtime frame: #{e.message}", secrets: @secrets)
        close_with(ClosedError.new(message))
      rescue StandardError => e
        closed_error = ClosedError.new(Redaction.message(e.message, secrets: @secrets))
        closed_error.set_backtrace(e.backtrace)
        close_with(closed_error)
      ensure
        close_with(ClosedError.new('realtime connection closed'))
      end

      def ensure_open!
        raise @closed_error if @closed

        self
      end

      def close_with(error)
        return if @closed

        @closed = true
        @closed_error = error
        @subscriptions.clear
        reject_pending(error)
        stop_callback_task
        close_socket
      end

      def reject_pending(error) = @pending.each_value { |queue| queue.enqueue(Failure.new(error: error)) }

      def write_frame(frame) = @write_lock.acquire { @socket.write("#{JSON.generate(frame)}\n") }

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
