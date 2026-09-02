# frozen_string_literal: true

module Volcano
  class Realtime
    class Protocol
      # Exposes connection state and manages publication handlers.
      module Lifecycle
        def connected? = !@closed

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
      end
      private_constant :Lifecycle
    end
  end
end
