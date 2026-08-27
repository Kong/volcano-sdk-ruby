# frozen_string_literal: true

module Volcano
  class Realtime
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

        if (error = frame['error'])
          reply_queue.enqueue(
            Protocol::Failure.new(
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
          next if @callback_queue.size >= @max_callback_queue

          @callback_queue.enqueue([handlers.dup, event, data])
        end
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
