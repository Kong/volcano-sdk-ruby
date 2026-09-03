# frozen_string_literal: true

module Volcano
  class Realtime
    # Coordinates a channel's protocol subscription and local lifecycle state.
    module ChannelLifecycle
      def mark_closed
        @closed = true
        @subscription_desired = @subscribed = false
        end_postgres_delivery
        reset_presence
      end

      def protocol_lost(protocol)
        @subscribed = false
        end_postgres_delivery
        detach_publication_handler(protocol)
        @handler_registered = false
        reset_presence
      end

      private

      def unsubscribe_protocol
        ensure_open!
        return clear_subscription_intent unless @subscribed

        protocol = @protocol_provider.call
        protocol.unsubscribe(channel: @name)
        complete_unsubscribe(protocol)
      end

      def clear_subscription_intent = @subscription_desired = false

      def complete_unsubscribe(protocol)
        @subscription_desired = @subscribed = false
        end_postgres_delivery
        invalidate_presence_subscription(protocol)
        clear_presence
      end

      def subscribe_protocol(protocol)
        epoch = next_presence_epoch
        begin_postgres_delivery
        register_handlers(protocol, epoch)
        protocol.subscribe(channel: @name, recoverable: presence?, join_leave: presence?)
        @subscribed = true
        [protocol, epoch]
      rescue StandardError
        end_postgres_delivery
        invalidate_presence_subscription(protocol)
        raise
      end

      def detach_from_protocol
        return unless @subscribed || @publication_handler

        protocol = @protocol_provider.call
        protocol.unsubscribe(channel: @name) if @subscribed && protocol.connected?
        detach_publication_handler(protocol)
      end

      def mark_removed
        @callbacks.each_value(&:clear)
        @handler_registered = @subscription_desired = @subscribed = false
        end_postgres_delivery
        reset_presence
        @closed = true
      end
    end
    private_constant :ChannelLifecycle
  end
end
