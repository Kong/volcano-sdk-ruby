# frozen_string_literal: true

module Volcano
  class Realtime
    # Dispatches protocol replies and publications to their waiting consumers.
    module ProtocolDispatch
      private

      def process(frame)
        if frame.empty?
          write_frame({})
        elsif frame.key?('id')
          dispatch_reply(frame)
        elsif frame.key?('push')
          dispatch_publication(frame.fetch('push'))
        end
      end

      def dispatch_reply(frame)
        reply_queue = @pending[frame.fetch('id')]
        return unless reply_queue

        reply_queue.enqueue(reply_value(frame))
      end

      def reply_value(frame)
        error = frame['error']
        return frame['result'] || frame.except('id') unless error

        message = error['message'] || 'realtime command failed'
        Protocol::Failure.new(error: ServerError.new(message, code: error['code']))
      end

      def dispatch_publication(push)
        channel = push['channel'].to_s
        data = push.dig('pub', 'data')
        return unless data.is_a?(Hash)

        event = data['event']
        registered_channel = @publication_handlers.each_key.select do |candidate|
          channel == candidate || channel.end_with?(":#{candidate}")
        end.max_by(&:length)
        return unless registered_channel
        return if @callback_queue.size >= @max_callback_queue

        @callback_queue.enqueue([@publication_handlers.fetch(registered_channel).dup, event, data])
      end

      def dispatch_callbacks
        until @callback_stopping
          handlers, event, data = @callback_queue.dequeue
          handlers.each do |handler|
            break if @callback_stopping

            handler.call(event, data)
          rescue StandardError
            next
          end
        end
      end
    end
  end
end
