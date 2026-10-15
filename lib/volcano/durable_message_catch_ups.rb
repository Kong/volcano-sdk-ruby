# frozen_string_literal: true

module Volcano
  # Runs a durable message stream's own work one job at a time: the catch-ups
  # it starts itself, the release of the live messages it holds, and the wait
  # before retrying a catch-up that failed, half a second doubling to 30
  # seconds. It runs in a task of its own rather than the realtime
  # connection's, which a reconnect stops midway.
  class DurableMessageCatchUps
    FIRST_RETRY_SECONDS = 0.5
    MAX_RETRY_SECONDS = 30.0
    private_constant :FIRST_RETRY_SECONDS, :MAX_RETRY_SECONDS

    # +read+ runs a catch-up that was asked for, +release+ delivers the held
    # live messages, +due+ asks for a catch-up once a retry's wait is over, and
    # +on_failure+ hears about a job that failed.
    def initialize(read, release, due, on_failure)
      @read = read
      @release = release
      @due = due
      @on_failure = on_failure
      @backoff = FIRST_RETRY_SECONDS
      @retry_delay = @task = @wake = nil
      @pending = @releasing = @closed = false
    end

    # The task is a transient child of the caller's, so call it from the task
    # that subscribes.
    def start
      @task ||= Async::Task.current.async(transient: true) { work }
      nil
    end

    def request
      @pending = true
      wake.signal
      nil
    end

    def release
      @releasing = true
      wake.signal
      nil
    end

    # Whether a catch-up asked for has yet to start reading.
    def pending? = @pending

    def retry_later
      return if @closed

      @retry_delay = @backoff
      @backoff = [@backoff * 2, MAX_RETRY_SECONDS].min
      wake.signal
      nil
    end

    def cancel_retry = @retry_delay = nil

    def caught_up = @backoff = FIRST_RETRY_SECONDS

    # Not stopped: the catch-up it is running may be what closed it.
    def close
      @closed = true
      wake.signal
      nil
    end

    private

    def work
      until @closed
        job = next_job
        job ? run(job) : await_request
      end
    end

    # A catch-up goes first: it releases the held messages itself.
    def next_job
      if @pending
        @pending = false
        @read
      elsif @releasing
        @releasing = false
        @release
      end
    end

    def run(job)
      job.call
    rescue StandardError => e
      @on_failure.call(e)
    end

    def await_request
      delay = @retry_delay
      return wake.wait unless delay

      Async::Task.current.with_timeout(delay) { wake.wait }
    rescue Async::TimeoutError
      @due.call
    end

    def wake
      require 'async/notification'
      @wake ||= Async::Notification.new
    end
  end
  private_constant :DurableMessageCatchUps
end
