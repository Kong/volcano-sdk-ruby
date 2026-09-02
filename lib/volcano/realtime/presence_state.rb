# frozen_string_literal: true

module Volcano
  class Realtime
    # Maintains immutable presence state independently of protocol lifecycle.
    module PresenceState
      private

      def replace_presence(clients)
        clients = {} unless clients.is_a?(Hash)
        @presence_state = clients.to_h do |client_id, info|
          [client_id.to_s.freeze, presence_info(info, client_id)]
        end.freeze
      end

      def apply_presence_event(event, info, epoch)
        return unless info.is_a?(Hash)

        presence_lock.acquire do
          next unless active_presence_epoch?(epoch)

          snapshot = presence_info(info, info['client'])
          update_presence_state(event, snapshot)
          [snapshot, @presence_state]
        end
      end

      def update_presence_state(event, snapshot)
        next_state = @presence_state.dup
        event == 'join' ? next_state[snapshot.client] = snapshot : next_state.delete(snapshot.client)
        @presence_state = next_state.freeze
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
          @presence_state
        end
      end

      def reset_presence
        @subscription_epoch += 1
        @presence_state = Immutable.call({})
        @tracked_state = Immutable.call({})
      end
    end
    private_constant :PresenceState
  end
end
