# frozen_string_literal: true

module Volcano
  class Realtime
    # Registers channel callbacks and connects them to protocol pushes.
    module ChannelCallbacks
      def on(event, callback = nil, &block)
        raise ArgumentError, "unsupported realtime event: #{event}" unless allowed_event?(event)

        @callbacks[event] << (callback || block || raise(ArgumentError, 'callback or block is required'))
        self
      end

      private

      def allowed_event?(event)
        event == 'message' || (presence? && %w[join leave presence_sync].include?(event))
      end

      def register_handlers(protocol)
        return if @handler_registered

        @publication_handler = protocol.on_publication(@name) do |event, data|
          emit('message', data) if event == 'message'
        end
        register_presence_handler(protocol)
        @handler_registered = true
      end

      def emit(event, data)
        @callbacks[event].dup.each { |callback| callback.call(data) }
      end

      def detach_publication_handler(protocol)
        protocol.off_publication(@name, @publication_handler) if @publication_handler
        detach_presence_handler(protocol)
        @publication_handler = nil
      end
    end
    private_constant :ChannelCallbacks
  end
end
