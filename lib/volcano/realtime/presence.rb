# frozen_string_literal: true

module Volcano
  class Realtime
    # Presence behavior mixed into realtime channels.
    module Presence
      def on_presence_sync(callback = nil, &)
        ensure_presence!
        on('presence_sync', callback, &)
      end

      def track(state = {})
        with_lifecycle_lock do
          ensure_open!
          ensure_presence!
          raise ClosedError, 'realtime channel is not subscribed' unless @subscribed
          raise ArgumentError, 'presence state must be a hash' unless state.is_a?(Hash)

          @tracked_state = Immutable.call(state)
        end
        nil
      end

      def presence_state = @presence_state
      def tracked_state = @tracked_state

      alias get_presence_state presence_state

      private

      def initialize_presence(type)
        @type = type
        @presence_state = Immutable.call({})
        @tracked_state = Immutable.call({})
        @presence_handler = nil
        @presence_lock = nil
        @subscription_epoch = 0
      end

      def presence? = @type == :presence

      def ensure_presence!
        return if presence?

        raise ArgumentError, 'operation is only available for presence channels'
      end

      def register_presence_handler(protocol, epoch)
        return unless presence?

        detach_presence_handler(protocol)
        @presence_handler = protocol.on_presence(@name) do |event, info|
          presence_event(event, info, epoch)
        end
      end

      def sync_presence(protocol, epoch)
        return unless presence?

        emit_presence_sync(fetch_presence_state(protocol, epoch))
      rescue StandardError => e
        report_presence_error(protocol, epoch, e)
      end

      def fetch_presence_state(protocol, epoch)
        presence_lock.acquire do
          next unless active_presence_epoch?(epoch)

          result = protocol.presence(channel: @name)
          replace_presence(result['presence']) if active_presence_epoch?(epoch)
        end
      end

      def presence_event(event, info, epoch)
        return sync_presence(@protocol_provider.call, epoch) if event == 'sync_required'

        delivery = apply_presence_event(event, info, epoch)
        return unless delivery

        snapshot, state = delivery
        emit(event, snapshot)
        emit('presence_sync', state) if active_presence_epoch?(epoch)
      end

      def emit_presence_sync(state)
        emit('presence_sync', state) if state
      end

      def report_presence_error(protocol, epoch, error)
        return unless protocol.connected? && active_presence_epoch?(epoch)

        @realtime.__send__(:report_channel_error, error)
      end

      def next_presence_epoch
        @subscription_epoch += 1
      end

      def active_presence_epoch?(epoch)
        @subscribed && epoch == @subscription_epoch
      end

      def invalidate_presence_subscription(protocol)
        return unless presence?

        @subscription_epoch += 1
        detach_presence_handler(protocol)
      end

      def detach_presence_handler(protocol)
        protocol.off_presence(@name, @presence_handler) if @presence_handler
        @presence_handler = nil
      end

      def presence_lock
        require 'async/semaphore'
        @presence_lock ||= Async::Semaphore.new(1)
      end
    end
    private_constant :Presence
  end
end
