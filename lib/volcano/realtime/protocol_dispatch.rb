# frozen_string_literal: true

module Volcano
  class Realtime
    # Dispatches protocol replies and publications to their waiting consumers.
    module ProtocolDispatch
      # @dynamic write_frame, dispatch_publication, dispatch_queued_callback, close_with, closed_error
      PresenceDelivery = Data.define(:handlers, :event, :data)

      private

      def process(frame)
        if frame.empty?
          write_frame({})
        elsif frame.key?('id')
          dispatch_reply(frame)
        elsif frame.key?('push')
          push = frame.fetch('push')
          raise TypeError, 'realtime push must be an object' unless push.is_a?(Hash)

          dispatch_push(push)
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
        id = frame.fetch('id')
        return unless id.is_a?(Integer)

        pending = @pending.fetch(id, nil)
        return unless pending

        reply = reply_value(frame, pending.reply_key)
        pending.queue.enqueue(apply_reply_hook(pending, reply))
      end

      def apply_reply_hook(pending, reply)
        return reply if reply.is_a?(Protocol::Failure) || !pending.on_reply

        pending.on_reply.call(reply)
        reply
      rescue StandardError => e
        Protocol::Failure.new(error: e)
      end

      def reply_value(frame, reply_key)
        error = frame['error']
        return successful_reply(frame, reply_key) unless error

        raise TypeError, 'realtime error must be an object' unless error.is_a?(Hash)

        message = error['message'] || 'realtime command failed'
        Protocol::Failure.new(error: ServerError.new(message, code: error['code']))
      end

      def successful_reply(frame, reply_key)
        frame.fetch(reply_key) { frame.fetch('result') { frame.except('id') } }
      end

      def dispatch_presence(push, event)
        channel = matching_channel(@presence_handlers, push['channel'].to_s)
        info = push.dig(event, 'info')
        return unless channel && info.is_a?(Hash)

        if @callback_queue.size >= @max_callback_queue
          @pending_presence_resyncs[channel] = @presence_handlers.fetch(channel).dup
          return
        end

        delivery = PresenceDelivery.new(handlers: @presence_handlers.fetch(channel).dup, event:, data: info)
        @callback_queue.enqueue(delivery)
      end

      def matching_channel(handlers, channel)
        handlers.each_key.select do |candidate|
          if candidate.start_with?('postgres:')
            postgres_channel?(candidate, channel)
          else
            channel == candidate || channel.end_with?(":#{candidate}")
          end
        end.max_by(&:length)
      end

      def postgres_channel?(candidate, channel)
        candidate_parts = candidate.split(':')
        channel_parts = channel.split(':')
        candidate_parts.length == 3 && candidate_parts.first == 'postgres' &&
          channel_parts.length == 5 && channel_parts.slice(1, 3) == candidate_parts
      end

      def dispatch_callbacks
        until @callback_stopping
          delivery = @callback_queue.dequeue
          dispatch_queued_callback(delivery)
          enqueue_pending_presence_resync
        end
      rescue StandardError => e
        close_with(closed_error(e), notify_error: true)
      end

      def dispatch_callback_delivery(handlers, event, data)
        handlers.each do |handler|
          break handlers if @callback_stopping

          handler.call(event, data)
        rescue StandardError
          next
        end
      end

      def enqueue_pending_presence_resync
        return if @callback_queue.size >= @max_callback_queue

        channel, handlers = @pending_presence_resyncs.shift
        return unless channel && handlers

        # @type var empty_info: Hash[String, Object?]
        empty_info = {}
        @callback_queue.enqueue(PresenceDelivery.new(handlers:, event: 'sync_required', data: empty_info))
      end
    end
  end
end
