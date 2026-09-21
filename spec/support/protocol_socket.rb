# frozen_string_literal: true

require 'async/queue'
require 'json'

module SpecSupport
  class ProtocolSocket
    attr_accessor :on_write
    attr_reader :writes

    def initialize
      @incoming = Async::Queue.new
      @writes = []
      @closed = false
    end

    def write(message)
      value = message.to_str
      @writes << value
      on_write&.call(JSON.parse(value))
    end

    def flush; end

    def read
      @incoming.dequeue
    end

    def receive(*frames)
      @incoming.enqueue(frames.join("\n"))
    end

    def receive_raw(frame)
      @incoming.enqueue(frame)
    end

    def finish
      @incoming.enqueue(nil)
    end

    def close
      return if @closed

      @closed = true
      finish
    end

    def closed?
      @closed
    end
  end
end
