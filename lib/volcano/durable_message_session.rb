# frozen_string_literal: true

module Volcano
  # Binds a subscription to the session signed in when it opened, as Postgres
  # delivery does. Signing out, signing in again, or setting another session
  # ends it; refreshing its token does not. Once ended, the stream reads and
  # delivers nothing more, rather than another user's messages, and the
  # subscription leaves the execution's channel.
  #
  # It follows the channel for the stream: a reconnect restores the channel
  # only while the session is the one that subscribed.
  class DurableMessageSession
    CHANGED = "The session that subscribed to the execution's messages has changed; " \
              'the subscription has ended'
    private_constant :CHANGED

    def initialize(realtime)
      @realtime = realtime
      _, @lineage, = realtime.__send__(:capture_session_binding)
    end

    # A stream that delivers to +handler+ and reads with +list_after+ while
    # the session is unchanged, and raises Error::SessionChangedError after.
    def stream(handler, list_after, on_failure)
      @stream = DurableMessageStream.new(bind(handler), bind_read(list_after), on_failure)
    end

    # Ends +subscription+ once the session changes. Called before the
    # subscription subscribes, so before anything checks the session.
    def end_with(subscription)
      @subscription = subscription
    end

    # Asked before a reconnect restores the channel.
    def restoring = require_session

    # Told when the server refuses to restore the channel for good.
    def refused = @subscription.unsubscribe

    def resubscribed = @stream.resubscribed
    def dropped = @stream.dropped
    def close = @stream.close

    private

    def bind(callable)
      lambda do |argument|
        require_session
        callable.call(argument)
      end
    end

    # A page read while the session changed is not delivered, even an empty
    # one, which delivers nothing that would check it.
    def bind_read(list_after)
      lambda do |after|
        require_session
        list_after.call(after).tap { require_session }
      end
    end

    def require_session
      _, lineage, session = @realtime.__send__(:capture_session_binding)
      return if session && lineage == @lineage

      @stream.close
      @subscription.unsubscribe
      raise Error::SessionChangedError, CHANGED
    end
  end
  private_constant :DurableMessageSession
end
