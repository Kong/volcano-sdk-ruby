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
          leave_durable_channel(channel) if forget_durable_channel(channel) && !@closed
        end
        nil
      rescue Async::Cancel
        # Stopped waiting for the lock, so the channel is still subscribed.
        abandon_durable_leave(channel) { protocol.drop } if forget_durable_channel(channel)
        raise
      end

      def forget_durable_channel(channel)
        @channels.delete(channel.name) if @channels[channel.name].equal?(channel)
      end

      # A leave the server did not confirm may have left the subscription in
      # place, so the connection is dropped, which ends it. The reconnect
      # restores only the channels still in use.
      def leave_durable_channel(channel)
        channel.__send__(:remove)
      rescue StandardError => e
        abandon_durable_leave(channel) { protocol.close }
        report_channel_error(e)
      rescue Async::Cancel
        # Closing here would start the reconnect in the task being stopped.
        abandon_durable_leave(channel) { protocol.drop }
        raise
      end

      def abandon_durable_leave(channel)
        channel.mark_closed
        yield if connected?
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
