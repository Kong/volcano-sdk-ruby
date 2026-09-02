# frozen_string_literal: true

module Volcano
  class Realtime
    # Channel collection and connection-state lifecycle operations.
    module Lifecycle
      def connected? = !@protocol.nil? && !@closed

      def remove_channel(name)
        @channels.delete("broadcast:#{name}")&.unsubscribe
        nil
      end

      def remove_all_channels
        channels = @channels.values
        @channels.clear
        first_error = nil
        channels.each do |channel|
          channel.unsubscribe
        rescue StandardError => e
          first_error ||= e
        end
        raise first_error if first_error

        nil
      end
    end
    private_constant :Lifecycle
  end
end
