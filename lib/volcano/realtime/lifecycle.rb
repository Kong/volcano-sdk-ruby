# frozen_string_literal: true

module Volcano
  class Realtime
    # Channel collection and connection-state lifecycle operations.
    module Lifecycle
      def connected? = !@closed && (@protocol&.connected? || false)

      def remove_channel(name)
        channel_lock.acquire { remove_channel_locked("broadcast:#{name}") }
        nil
      end

      def remove_all_channels
        first_error = channel_lock.acquire do
          @channels.dup.filter_map do |name, channel|
            remove_channel_entry(name, channel)
          end.first
        end
        raise first_error if first_error

        nil
      end

      private

      def remove_channel_locked(name)
        channel = @channels[name]
        return unless channel

        channel.remove
        @channels.delete(name)
      end

      def remove_channel_entry(name, channel)
        channel.remove
        @channels.delete(name)
        nil
      rescue StandardError => e
        e
      end
    end
    private_constant :Lifecycle
  end
end
