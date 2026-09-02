# frozen_string_literal: true

module Volcano
  class Realtime
    # Channel collection and connection-state lifecycle operations.
    module Lifecycle
      def connected? = !@closed && (@protocol&.connected? || false)

      def remove_channel(name)
        key = "broadcast:#{name}"
        channel = @channels[key]
        return nil unless channel

        channel.remove
        @channels.delete(key)
        nil
      end

      def remove_all_channels
        @channels.dup.each do |name, channel|
          channel.remove
          @channels.delete(name)
        end
        nil
      end
    end
    private_constant :Lifecycle
  end
end
