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

        private

        def close_with(error, notify_error: false)
          return if @closed

          was_connected = @connected
          close_state(error)
          notify_protocol_error(error) if notify_error
          stop_protocol(error)
          notify_protocol_close(error) if was_connected
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
        def notify_protocol_close(error) = @events&.on_close&.call(error)
      end
      private_constant :Lifecycle
    end
  end
end
