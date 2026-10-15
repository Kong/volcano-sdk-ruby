# frozen_string_literal: true

module Volcano
  # Binds a subscription to the session signed in when it opened, as Postgres
  # delivery does. Signing out, signing in again, or setting another session
  # ends it; refreshing its token does not. Once ended, the stream reads and
  # delivers nothing more, rather than another user's messages, and the
  # subscription leaves the execution's channel.
  class DurableMessageSession
    CHANGED = "The session that subscribed to the execution's messages has changed; " \
              'the subscription has ended'
    private_constant :CHANGED

    def initialize(realtime)
      @realtime = realtime
      @subscription = nil
      _, @lineage, = realtime.__send__(:capture_session_binding)
    end

    # A stream that delivers to +handler+ and reads with +list_after+ while
    # the session is unchanged, and raises Error::SessionChangedError after.
    def stream(handler, list_after, on_failure)
      @stream = DurableMessageStream.new(bind(handler), bind(list_after), on_failure)
    end

    # Ends +subscription+ once the session changes. Until then, leaving the
    # channel is up to whoever opens it.
    def end_with(subscription)
      @subscription = subscription
    end

    private

    def bind(callable)
      lambda do |argument|
        require_session
        callable.call(argument)
      end
    end

    def require_session
      _, lineage, session = @realtime.__send__(:capture_session_binding)
      return if session && lineage == @lineage

      @stream.close
      @subscription&.unsubscribe
      raise Error::SessionChangedError, CHANGED
    end
  end
  private_constant :DurableMessageSession
end
