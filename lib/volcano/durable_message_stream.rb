# frozen_string_literal: true

module Volcano
  # Delivers the messages a durable execution publishes in `seq` order, once
  # each, from its realtime channel and from the messages list.
  #
  # A live message can only be delivered once everything before it has been
  # listed, or the missed ones would fall below the last delivered `seq` and be
  # skipped. So live messages are held until the first catch-up starts, and
  # while any catch-up is reading, then released in order.
  #
  # The channel itself drops publications while it is not subscribed, and
  # reports each resubscription, which starts a catch-up of what it dropped.
  class DurableMessageStream
    include DurableMessageResponses

    # +list_after+ reads the page of published messages after a `seq`, and
    # +on_failure+ hears about a catch-up that failed in the background.
    def initialize(handler, list_after, on_failure)
      @handler = handler
      @list_after = list_after
      @on_failure = on_failure
      @last_seq = @catch_ups = 0
      @started = @closed = false
      @held = []
      @reads = nil
    end

    def live(data)
      message = published(data)
      return unless message
      return hold(message) if !@started || @catch_ups.positive?

      deliver(message)
    end

    # A failed catch-up leaves the gap until the next one; live delivery goes on.
    def resubscribed
      begin_catch_up
      Async::Task.current.async do
        read_missed
      rescue StandardError => e
        @on_failure.call(e)
      end
      nil
    end

    # Reads what was missed, then releases the held messages. Raises the
    # list's or the handler's error.
    def catch_up
      begin_catch_up
      read_missed
    end

    # Not stopped: the handler a catch-up is running may be what closed it.
    def close
      @closed = true
    end

    private

    # Counted before the read waits its turn, so nothing is delivered live
    # meanwhile.
    def begin_catch_up
      @started = true
      @catch_ups += 1
    end

    def read_missed
      reads.acquire do
        read_pages
      ensure
        # Released by the last catch-up only, and while still counted, so a
        # live message that arrives meanwhile is held behind the released ones.
        release if @catch_ups == 1
      end
    ensure
      @catch_ups -= 1
    end

    def read_pages
      until @closed
        page = @list_after.call(@last_seq)
        page.messages.each { |message| deliver(message) }
        return if !page.has_more || page.messages.empty?
      end
    end

    def release
      until @held.empty?
        held = @held.sort_by(&:seq)
        @held = []
        held.each { |message| deliver(message) }
      end
    end

    def hold(message)
      @held << message
      nil
    end

    def deliver(message)
      return if @closed || message.seq <= @last_seq

      @last_seq = message.seq
      @handler.call(message)
      nil
    end

    def published(data)
      message = durable_message(data)
      message if message.direction == 'out'
    rescue TypeError
      nil
    end

    def reads
      require 'async/semaphore'
      @reads ||= Async::Semaphore.new(1)
    end
  end
  private_constant :DurableMessageStream
end
