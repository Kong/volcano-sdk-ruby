# frozen_string_literal: true

module Volcano
  class Realtime
    # Channel collection and connection-state lifecycle operations.
    module Lifecycle
      # @dynamic channel_lock, normalize_channel_type, report_channel_error, protocol
      def connected? = !@closed && (@protocol&.connected? || false)

      def remove_channel(name, type: :broadcast)
        channel_type = normalize_channel_type(type)
        channel_lock.acquire { remove_channel_locked("#{channel_type}:#{name}") }
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
        channel = @channels.fetch(name, nil)
        return unless channel

        channel.__send__(:remove)
        @channels.delete(name)
      end

      # Leaves a durable channel unless a later subscription replaced it. Once
      # the connection is closed there is nothing left to leave.
      def remove_durable_channel(channel)
        channel_lock.acquire do
          if @channels[channel.name].equal?(channel)
            @channels.delete(channel.name)
            leave_durable_channel(channel) unless @closed
          end
        end
        nil
      end

      # A leave the server did not confirm may have left the subscription in
      # place, so the connection is dropped, which ends it. The reconnect
      # restores only the channels still in use.
      def leave_durable_channel(channel)
        channel.__send__(:remove)
      rescue StandardError => e
        channel.mark_closed
        protocol.close if connected?
        report_channel_error(e)
      end

      def remove_channel_entry(name, channel)
        channel.__send__(:remove)
        @channels.delete(name)
        nil
      rescue StandardError => e
        e
      end
    end
    private_constant :Lifecycle
  end
end
