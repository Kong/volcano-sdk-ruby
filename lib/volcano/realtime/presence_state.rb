# frozen_string_literal: true

module Volcano
  class Realtime
    # Maintains immutable presence state independently of protocol lifecycle.
    module PresenceState
      # @dynamic presence_lock, active_presence_epoch?, presence?

      private

      def replace_presence(clients)
        unless clients.is_a?(Hash)
          # @type var empty_clients: Hash[String, Object?]
          empty_clients = {}
          clients = empty_clients
        end
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
        # @type var empty_data: Hash[String, json_value]
        empty_data = {}
        raw_data = info['conn_info']
        data = raw_data.is_a?(Hash) ? raw_data : empty_data
        PresenceInfo.new(
          client: info.fetch('client', fallback_client).to_s,
          user: info['user']&.to_s,
          data: data
        )
      end

      def clear_presence
        return unless presence?

        presence_lock.acquire do
          # @type var empty_presence: Hash[String, PresenceInfo]
          empty_presence = {}
          # @type var empty_tracked: Hash[String, json_value]
          empty_tracked = {}
          @presence_state = Immutable.call(empty_presence)
          @tracked_state = Immutable.call(empty_tracked)
          @presence_state
        end
      end

      def reset_presence
        @subscription_epoch += 1
        # @type var empty_presence: Hash[String, PresenceInfo]
        empty_presence = {}
        # @type var empty_tracked: Hash[String, json_value]
        empty_tracked = {}
        @presence_state = Immutable.call(empty_presence)
        @tracked_state = Immutable.call(empty_tracked)
      end
    end
    private_constant :PresenceState
  end
end
