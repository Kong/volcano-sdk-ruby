# frozen_string_literal: true

module Volcano
  class Realtime
    # Follows a durable execution's messages on a channel.
    module DurableChannel
      # @dynamic durable?

      private

      # +data+ goes with every subscribe, including the ones a reconnect
      # restores. +follower+ is asked before each of those restores, hears each
      # one and each publication the connection dropped, and is closed with the
      # channel.
      def follow_durable(data, follower)
        @subscribe_data = data
        @follower = follower
      end

      # A durable channel's follower reads back what the connection dropped.
      def publication_rejection(protocol, generation)
        follower = @follower
        follower ? ->(_publication) { follower.dropped } : super
      end

      # The server refuses a durable subscribe for good once the execution is
      # gone or hidden from the session, so the follower ends the subscription
      # instead of the reconnect retrying it, and the refusal says so.
      def restore_refused(error)
        follower = @follower
        return error unless follower
        return error if error.temporary?

        follower.refused
        ServerError.new("#{error.message}; the durable message subscription has ended", code: error.code)
      end

      # The server authorizes a durable subscribe by the socket's session, so
      # the socket must belong to the client's current one.
      def prepare_protocol_subscription(protocol, epoch)
        @realtime.__send__(:capture_protocol_session) if durable?
        super
      end
    end
    private_constant :DurableChannel
  end
end
