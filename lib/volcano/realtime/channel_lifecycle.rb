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
        remember_recovery_position(protocol)
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
        if broadcast?
          remember_recovery_position(protocol)
          detach_publication_handler(protocol)
          @handler_registered = false
        end
        @subscription_desired = @subscribed = false
        end_postgres_delivery
        invalidate_presence_subscription(protocol)
        clear_presence
      end

      def subscribe_protocol(protocol)
        epoch = next_presence_epoch
        recovery_binding = recovery_binding()
        prepare_protocol_subscription(protocol, epoch)
        complete_protocol_subscription(protocol, epoch, recovery_binding)
      rescue StandardError => e
        reject_failed_subscription(protocol, e)
        end_postgres_delivery
        invalidate_presence_subscription(protocol)
        raise
      end

      def complete_protocol_subscription(protocol, epoch, recovery_binding)
        protocol.subscribe(channel: @name, **subscription_options(recovery_binding))
        validate_recovery_binding!(recovery_binding)
        remember_recovery_position(protocol)
        @subscribed = true
        [protocol, epoch]
      end

      def prepare_protocol_subscription(protocol, epoch)
        begin_postgres_delivery
        register_handlers(protocol, epoch)
      end

      def detach_from_protocol
        return unless @subscribed || @publication_handler

        protocol = @protocol_provider.call
        protocol.unsubscribe(channel: @name) if @subscribed && protocol.connected?
        detach_publication_handler(protocol)
      end

      def subscription_options(binding) = { recovery: binding&.last, recoverable: presence?, join_leave: presence? }

      def recovery_binding
        return unless broadcast?

        _, lineage, = @realtime.__send__(:capture_protocol_session)
        [lineage, recovery_position(lineage)].freeze
      end

      def recovery_position(lineage)
        return @recovery_position if @recovery_lineage == lineage

        @recovery_lineage = lineage
        @recovery_position = {}.freeze
      end

      def validate_recovery_binding!(binding)
        return unless binding

        _, lineage, = @realtime.__send__(:capture_protocol_session)
        raise Error::SessionChangedError unless lineage == binding.first
      end

      def reject_failed_subscription(protocol, error)
        detach_publication_handler(protocol)
        @handler_registered = false
        protocol.close if protocol.connected? && !error.is_a?(ServerError)
      end

      def remember_recovery_position(protocol)
        return unless broadcast?

        @recovery_position = protocol.__send__(:position, @name) || @recovery_position
      end

      def clear_channel_recovery_state
        return unless broadcast?

        @recovery_position = {}.freeze
        @recovery_lineage = nil
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
