# frozen_string_literal: true

require 'async/queue'
require 'json'

module SpecSupport
  class RealtimeAuthTransport
    def auth_signin(**)
      Volcano::Transport::Response.new(
        status: 200,
        body: {
          'access_token' => 'access-token',
          'refresh_token' => 'refresh-token',
          'user' => { 'id' => 'user-123' }
        },
        headers: {},
        data: nil
      )
    end
  end

  class RealtimeDatabaseTransport < RealtimeAuthTransport
    attr_reader :queries, :query_threads

    def initialize(rows = [{ 'id' => 42, 'body' => 'fetched' }], error: nil)
      super()
      @rows = rows
      @error = error
      @queries = []
      @query_threads = []
    end

    def query_database_select(**arguments)
      @queries << arguments
      @query_threads << Thread.current
      raise @error if @error

      Volcano::Transport::Response.new(
        status: 200,
        body: { 'data' => @rows },
        headers: {},
        data: nil
      )
    end
  end

  class BlockingRealtimeDatabaseTransport < RealtimeDatabaseTransport
    attr_reader :started, :release

    def initialize
      super
      @started = ThreadSignalQueue.new
      @release = ThreadSignalQueue.new
    end

    def query_database_select(**arguments)
      @started.enqueue(true)
      @release.dequeue
      super
    end
  end

  class FirstBlockingRealtimeDatabaseTransport < RealtimeDatabaseTransport
    attr_reader :release, :started

    def initialize
      super
      @blocked = false
      @started = ThreadSignalQueue.new
      @release = ThreadSignalQueue.new
    end

    def query_database_select(**arguments)
      unless @blocked
        @blocked = true
        @started.enqueue(true)
        @release.dequeue
      end
      super
    end
  end

  class ThreadSignalQueue < Queue
    alias dequeue pop
    alias enqueue push
  end

  class FacadeSocket
    attr_accessor :on_write
    attr_reader :commands, :reading

    def initialize
      @incoming = Async::Queue.new
      @commands = []
      @buffer = []
      @closed = false
    end

    def write(frame)
      @buffer << frame
    end

    def flush
      dispatch(@buffer.shift) until @buffer.empty?
    end

    def dispatch(frame)
      command = JSON.parse(frame.to_str)
      @commands << command
      return if on_write&.call(command) == :defer

      result = command.key?('connect') ? { 'client' => 'client-123' } : {}
      respond(command.fetch('id'), result: result)
    end

    def read
      flush
      @reading = true
      value = @incoming.dequeue
      raise value if value.is_a?(Exception)

      value
    ensure
      @reading = false
    end

    def publication(channel:, data:)
      @incoming.enqueue(
        JSON.generate(
          'push' => {
            'channel' => channel,
            'pub' => { 'data' => data }
          }
        )
      )
    end

    def presence_event(channel:, event:, info:)
      @incoming.enqueue(
        JSON.generate(
          'push' => {
            'channel' => channel,
            event => { 'info' => info }
          }
        )
      )
    end

    def respond(id, result: {})
      command = @commands.reverse_each.find { |item| item.fetch('id') == id }
      reply_key = command.keys.find { |key| key != 'id' }
      @incoming.enqueue(JSON.generate('id' => id, reply_key => result))
    end

    def receive_raw(frame)
      @incoming.enqueue(frame)
    end

    def reject(id, message, code: nil)
      error = { 'message' => message }
      error['code'] = code if code
      @incoming.enqueue(JSON.generate('id' => id, 'error' => error))
    end

    def invalid_frame
      @incoming.enqueue('{')
    end

    def fail_read(error)
      @incoming.enqueue(error)
    end

    def connect_then_invalid(id)
      reply = JSON.generate('id' => id, 'connect' => { 'client' => 'client-123' })
      @incoming.enqueue("#{reply}\n{")
    end

    def close
      return if @closed

      @closed = true
      @incoming.enqueue(nil)
    end

    def closed?
      @closed
    end
  end
end
