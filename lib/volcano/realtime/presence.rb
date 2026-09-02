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
      end

      def presence? = @type == :presence

      def ensure_presence!
        return if presence?

        raise ArgumentError, 'operation is only available for presence channels'
      end

      def register_presence_handler(protocol)
        return unless presence? && !@presence_handler

        @presence_handler = protocol.on_presence(@name) do |event, info|
          presence_event(event, info)
        end
      end

      def sync_presence(protocol)
        return unless presence?

        presence_lock.acquire do
          result = protocol.presence(channel: @name)
          replace_presence(result['presence'])
        end
      rescue ServerError => e
        presence_lock.acquire { replace_presence({}) }
        @realtime.__send__(:report_channel_error, e)
      end

      def replace_presence(clients)
        clients = {} unless clients.is_a?(Hash)
        @presence_state = clients.to_h do |client_id, info|
          [client_id.to_s.freeze, presence_info(info, client_id)]
        end.freeze
        emit('presence_sync', @presence_state)
      end

      def presence_event(event, info)
        return unless info.is_a?(Hash)

        presence_lock.acquire do
          snapshot = presence_info(info, info['client'])
          next_state = @presence_state.dup
          event == 'join' ? next_state[snapshot.client] = snapshot : next_state.delete(snapshot.client)
          @presence_state = next_state.freeze
          emit(event, snapshot)
          emit('presence_sync', @presence_state)
        end
      end

      def presence_info(info, fallback_client)
        data = info['conn_info'].is_a?(Hash) ? info.fetch('conn_info') : {}
        PresenceInfo.new(
          client: info.fetch('client', fallback_client).to_s,
          user: info['user']&.to_s,
          data: data
        )
      end

      def clear_presence
        return unless presence?

        presence_lock.acquire do
          @presence_state = Immutable.call({})
          @tracked_state = Immutable.call({})
          emit('presence_sync', @presence_state)
        end
      end

      def reset_presence
        @presence_state = Immutable.call({})
        @tracked_state = Immutable.call({})
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
