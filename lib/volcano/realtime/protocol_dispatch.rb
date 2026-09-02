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
          dispatch_push(frame.fetch('push'))
        end
      end

      def dispatch_push(push)
        if push.key?('pub')
          dispatch_publication(push)
        elsif push.key?('join')
          dispatch_presence(push, 'join')
        elsif push.key?('leave')
          dispatch_presence(push, 'leave')
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
        registered_channel = matching_channel(@publication_handlers, channel)
        return unless registered_channel
        return if @callback_queue.size >= @max_callback_queue

        @callback_queue.enqueue([@publication_handlers.fetch(registered_channel).dup, event, data])
      end

      def dispatch_presence(push, event)
        channel = matching_channel(@presence_handlers, push['channel'].to_s)
        info = push.dig(event, 'info')
        return unless channel && info.is_a?(Hash)

        if @callback_queue.size >= @max_callback_queue
          @pending_presence_resyncs[channel] = @presence_handlers.fetch(channel).dup
          return
        end

        @callback_queue.enqueue([@presence_handlers.fetch(channel).dup, event, info])
      end

      def matching_channel(handlers, channel)
        handlers.each_key.select do |candidate|
          channel == candidate || channel.end_with?(":#{candidate}")
        end.max_by(&:length)
      end

      def dispatch_callbacks
        until @callback_stopping
          handlers, event, data = @callback_queue.dequeue
          dispatch_callback_delivery(handlers, event, data)
          enqueue_pending_presence_resync
        end
      end

      def dispatch_callback_delivery(handlers, event, data)
        handlers.each do |handler|
          break if @callback_stopping

          handler.call(event, data)
        rescue StandardError
          next
        end
      end

      def enqueue_pending_presence_resync
        return if @callback_queue.size >= @max_callback_queue

        channel, handlers = @pending_presence_resyncs.shift
        return unless channel

        @callback_queue.enqueue([handlers, 'sync_required', {}])
      end
    end
  end
end
