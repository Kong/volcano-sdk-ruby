# frozen_string_literal: true

module Volcano
  # Delivers the messages a durable execution publishes in `seq` order, once
  # each, from its realtime channel and from the messages list.
  #
  # A live message can only be delivered once everything before it has been
  # listed, or the missed ones would fall below the last delivered `seq` and be
  # skipped. So live messages are held until the first catch-up starts, while
  # any catch-up is reading, and while any held message still follows a gap.
  # A held message is released only once the message its broadcast names as
  # the one before it has been delivered.
  #
  # After the first catch-up, every message is delivered from the stream's own
  # task, one at a time. A live one is held and released there too, since a
  # reconnect stops the connection's tasks midway and would leave the block's
  # work on it unfinished.
  #
  # The channel itself drops publications while it is not subscribed, and
  # reports each resubscription, which starts a catch-up of what it dropped.
  # A broadcast naming a publish not yet delivered starts one too, since the
  # broadcast before it was lost or has yet to arrive, and so does a
  # publication the connection had no room for.
  class DurableMessageStream
    include DurableMessageResponses

    Held = Data.define(:message, :prev_seq)
    ENDED = 'the durable message subscription has ended'
    private_constant :Held, :ENDED

    # +list_after+ reads the page of published messages after a `seq`, and
    # +on_failure+ hears about a catch-up that failed in the background or a
    # handler that raised after the first catch-up.
    def initialize(handler, list_after, on_failure)
      require 'async/semaphore'
      @handler = handler
      @list_after = list_after
      @on_failure = on_failure
      @last_seq = @catch_ups = 0
      @started = @closed = false
      @held = DurableMessageBacklog.new
      @reads = Async::Semaphore.new(1)
      @background = DurableMessageCatchUps.new(
        -> { read_missed }, -> { release_live }, -> { catch_up_in_background }, on_failure
      )
    end

    def live(data)
      held = published(data) unless @closed
      return unless held

      waiting = behind?
      @held.hold(held)
      return if waiting
      return catch_up_in_background if held.prev_seq > @last_seq

      @background.release
    end

    def resubscribed = catch_up_in_background

    def dropped = catch_up_in_background

    # Reads what was missed, then releases the held messages. Raises the
    # list's or the handler's error, closing the stream before anything held
    # is delivered, and raises Realtime::ClosedError if the stream was closed
    # meanwhile. Call it from the task that subscribes, which the catch-ups
    # the stream starts itself run under. Those start once it has read, so
    # one asked for while subscribing cannot call the handler before the
    # read whose errors the subscriber hears.
    def catch_up
      begin_catch_up
      read_missed(first: true)
      @background.start unless @closed
      raise Realtime::ClosedError, ENDED if @closed
    end

    # Not stopped: the handler a catch-up is running may be what closed it.
    def close
      @closed = true
      @held.clear
      @background.close
    end

    private

    def behind? = !@started || @catch_ups.positive? || !@held.empty?

    # Delivers the held live messages that follow on from the last one
    # delivered, until a catch-up is asked for. One left behind a gap is read
    # back.
    def release_live
      while @catch_ups.zero? && (held = @held.take_following(@last_seq))
        deliver(held.message, report: true)
      end
      catch_up_in_background unless @held.empty?
    end

    # One catch-up waiting its turn reads whatever more are asked for
    # meanwhile, so a burst of dropped publications reads once.
    def catch_up_in_background
      return if @background.pending?

      begin_catch_up
      @background.request
    end

    # Counted before the read waits its turn, so nothing is delivered live
    # meanwhile. A catch-up replaces the retry that was waiting.
    def begin_catch_up
      @started = true
      @background.cancel_retry
      @catch_ups += 1
    end

    def read_missed(first: false)
      read = false
      @reads.acquire do
        read_pages(report: !first)
        read = true
      ensure
        close if first && !read
        # Released by the last catch-up only, and while still counted, so a
        # live message that arrives meanwhile is held behind the released ones.
        release(read, report: !first) if @catch_ups == 1
      end
    ensure
      @catch_ups -= 1
    end

    def read_pages(report:)
      until @closed
        after = @last_seq
        page = @list_after.call(after)
        page.messages.each { |message| deliver(message, report:) }
        # A page that delivered nothing would be asked for again unchanged.
        return if !page.has_more || @last_seq == after
      end
    end

    # Delivers the held messages that follow on from the last one delivered,
    # and retries the read while any is left behind a gap or the read failed.
    def release(read, report:)
      while (held = @held.take_following(@last_seq))
        deliver(held.message, report:)
      end
    ensure
      read && @held.empty? ? @background.caught_up : @background.retry_later
    end

    def deliver(message, report:)
      call_handler(message, report) unless @closed || message.seq <= @last_seq
    end

    # Only the first catch-up raises what the handler raised, to the caller
    # that subscribes. Later the stream's own task would lose it, so it is
    # reported and delivery goes on.
    def call_handler(message, report)
      @last_seq = message.seq
      @handler.call(message)
    rescue StandardError => e
      raise unless report

      @on_failure.call(e)
    end

    def published(data)
      message = durable_message(data)
      Held.new(message:, prev_seq: broadcast_prev_seq(data)) if message.direction == 'out'
    rescue TypeError
      nil
    end
  end
  private_constant :DurableMessageStream
end
