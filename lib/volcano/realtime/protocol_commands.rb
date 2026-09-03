# frozen_string_literal: true

module Volcano
  class Realtime
    # Builds Centrifuge protocol commands.
    module ProtocolCommands
      def connect(id:, token:) = { 'id' => id, 'connect' => { 'token' => token } }

      def subscribe(id:, channel:, recovery: nil, recoverable: false, join_leave: false)
        options = { 'channel' => channel }
        add_recovery(options, recovery) if recovery
        options['recoverable'] = true if recoverable
        options['join_leave'] = true if join_leave
        { 'id' => id, 'subscribe' => options }
      end

      def publish(id:, channel:, data:) = { 'id' => id, 'publish' => { 'channel' => channel, 'data' => data } }

      def unsubscribe(id:, channel:) = { 'id' => id, 'unsubscribe' => { 'channel' => channel } }

      def presence(id:, channel:) = { 'id' => id, 'presence' => { 'channel' => channel } }

      private

      def add_recovery(options, recovery)
        options['recover'] = true
        options['epoch'] = recovery.fetch(:epoch) if recovery.key?(:epoch)
        options['offset'] = recovery.fetch(:offset) if recovery.key?(:offset)
        options['positioned'] = options['recoverable'] = true
      end
    end
    private_constant :ProtocolCommands
  end
end
