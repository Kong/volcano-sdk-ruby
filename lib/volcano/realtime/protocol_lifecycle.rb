# frozen_string_literal: true

module Volcano
  class Realtime
    class Protocol
      # Exposes connection state and manages publication handlers.
      module Lifecycle
        def connected? = @connected && !@closed

        def on_publication(channel, &handler)
          ensure_open!
          @publication_handlers[channel] << handler
          handler
        end

        def off_publication(channel, handler)
          handlers = @publication_handlers[channel]
          handlers.delete(handler)
          @publication_handlers.delete(channel) if handlers.empty?
          nil
        end

        def on_presence(channel, &handler)
          ensure_open!
          @presence_handlers[channel] << handler
          handler
        end

        def off_presence(channel, handler)
          handlers = @presence_handlers[channel]
          handlers.delete(handler)
          @presence_handlers.delete(channel) if handlers.empty?
          @pending_presence_resyncs.delete(channel)
          nil
        end

        private

        def initialize_state
          @next_id = 0
          @pending = {}
          initialize_locks
          initialize_handlers
          initialize_recovery
          @callback_stopping = @connected = @closed = false
          @subscriptions = Set.new
          @closed_error = nil
        end

        def initialize_locks
          @write_lock = Async::Semaphore.new(1)
          @subscription_lock = Async::Semaphore.new(1)
        end

        def initialize_handlers
          @publication_handlers = Hash.new { |hash, key| hash[key] = [] }
          @presence_handlers = Hash.new { |hash, key| hash[key] = [] }
          @pending_presence_resyncs = {}
          @callback_queue = Async::LimitedQueue.new(@max_callback_queue)
        end

        def reject_pending(error)
          @pending.each_value { |pending| pending.queue.enqueue(Failure.new(error: error)) }
        end

        def close_socket
          @socket.close
        rescue StandardError
          nil
        end

        def stop_callback_task
          @callback_stopping = true
          @callback_task.stop unless @callback_task == Async::Task.current
        end

        def close_with(error, notify_error: false)
          return if @closed

          was_connected = @connected
          close_state(error)
          notify_protocol_error(error) if notify_error
          stop_protocol(error)
          if notify_error
            notify_protocol_failure(error, was_connected)
          elsif was_connected
            notify_protocol_close(error)
          end
        end

        def close_state(error)
          @connected = false
          @closed = true
          @closed_error = error
          @subscriptions.clear
        end

        def stop_protocol(error)
          reject_pending(error)
          stop_callback_task
          close_socket
        end

        def notify_protocol_error(error) = @events&.on_error&.call(error)
        def notify_protocol_failure(error, disconnected) = @events&.on_failure&.call(error, disconnected)
        def notify_protocol_close(error) = @events&.on_close&.call(error)
      end
      private_constant :Lifecycle
    end
  end
end
