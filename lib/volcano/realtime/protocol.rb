# frozen_string_literal: true

require 'async/queue'
require 'json'

module Volcano
  class Realtime
    class ServerError < StandardError
      attr_reader :code

      def initialize(message, code: nil)
        super(message)
        @code = code
      end
    end

    class ClosedError < StandardError; end
    class DuplicateSubscriptionError < StandardError; end

    class Protocol
      Failure = Data.define(:error)

      def self.connect(id:, token:)
        { 'id' => id, 'connect' => { 'token' => token } }
      end

      def self.subscribe(id:, channel:)
        { 'id' => id, 'subscribe' => { 'channel' => channel } }
      end

      def self.publish(id:, channel:, data:)
        { 'id' => id, 'publish' => { 'channel' => channel, 'data' => data } }
      end

      def self.unsubscribe(id:, channel:)
        { 'id' => id, 'unsubscribe' => { 'channel' => channel } }
      end

      def initialize(socket:, task: Async::Task.current)
        @socket = socket
        @next_id = 0
        @pending = {}
        @publication_handlers = Hash.new { |hash, key| hash[key] = [] }
        @subscriptions = Set.new
        @closed = false
        @reader_task = task.async { read_loop }
      end

      def connect(token:)
        request { |id| self.class.connect(id: id, token: token) }
      end

      def subscribe(channel:)
        ensure_open!
        raise DuplicateSubscriptionError, "already subscribed to #{channel}" if @subscriptions.include?(channel)

        result = request { |id| self.class.subscribe(id: id, channel: channel) }
        @subscriptions.add(channel)
        result
      end

      def publish(channel:, data:)
        request { |id| self.class.publish(id: id, channel: channel, data: data) }
      end

      def unsubscribe(channel:)
        ensure_open!
        return {} unless @subscriptions.include?(channel)

        result = request { |id| self.class.unsubscribe(id: id, channel: channel) }
        @subscriptions.delete(channel)
        result
      end

      def on_publication(channel, &block)
        ensure_open!
        @publication_handlers[channel] << block
        self
      end

      def close
        return if @closed

        @closed = true
        reject_pending(ClosedError.new('realtime connection closed'))
        @subscriptions.clear
        @reader_task.stop
        @socket.close
        nil
      end

      private

      def request
        ensure_open!
        @next_id += 1
        id = @next_id
        reply_queue = Async::Queue.new
        @pending[id] = reply_queue
        @socket.write("#{JSON.generate(yield(id))}\n")
        reply = reply_queue.dequeue
        raise reply.error if reply.is_a?(Failure)

        reply
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
        close_with(ClosedError.new("invalid realtime frame: #{e.message}"))
      rescue StandardError => e
        closed_error = ClosedError.new(e.message)
        closed_error.set_backtrace(e.backtrace)
        close_with(closed_error)
      ensure
        close_with(ClosedError.new('realtime connection closed'))
      end

      def process(frame)
        if frame.key?('id')
          dispatch_reply(frame)
        elsif frame.key?('push')
          dispatch_publication(frame.fetch('push'))
        end
      end

      def dispatch_reply(frame)
        reply_queue = @pending[frame.fetch('id')]
        return unless reply_queue

        if (error = frame['error'])
          reply_queue.enqueue(
            Failure.new(
              error: ServerError.new(error['message'] || 'realtime command failed', code: error['code'])
            )
          )
        else
          reply_queue.enqueue(frame['result'] || frame.except('id'))
        end
      end

      def dispatch_publication(push)
        channel = push['channel'].to_s
        data = push.dig('pub', 'data')
        return unless data.is_a?(Hash)

        event = data['event']
        @publication_handlers.each do |registered_channel, handlers|
          next unless channel == registered_channel || channel.end_with?(":#{registered_channel}")

          handlers.each { |handler| handler.call(event, data) }
        end
      end

      def ensure_open!
        raise ClosedError, 'realtime connection closed' if @closed
      end

      def close_with(error)
        return if @closed

        @closed = true
        @subscriptions.clear
        reject_pending(error)
      end

      def reject_pending(error)
        @pending.each_value { |reply_queue| reply_queue.enqueue(Failure.new(error: error)) }
      end
    end
  end
end
