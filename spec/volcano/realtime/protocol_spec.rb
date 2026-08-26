# frozen_string_literal: true

require 'async'
require 'async/condition'
require 'async/queue'
require 'json'
require 'spec_helper'

RSpec.describe Volcano::Realtime::Protocol do
  class FakeSocket
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

    def read
      @incoming.dequeue
    end

    def receive(*frames)
      @incoming.enqueue(frames.join("\n"))
    end

    def finish
      @incoming.enqueue(nil)
    end

    def close
      return if @closed

      @closed = true
      finish
    end
  end

  it 'builds the bounded JSON commands' do
    expect(described_class.connect(id: 1, token: 'access')).to eq(
      'id' => 1,
      'connect' => { 'token' => 'access' }
    )
    expect(described_class.subscribe(id: 2, channel: 'broadcast:contract')).to eq(
      'id' => 2,
      'subscribe' => { 'channel' => 'broadcast:contract' }
    )
    expect(
      described_class.publish(
        id: 3,
        channel: 'broadcast:contract',
        data: { 'event' => 'message', 'value' => 'contract' }
      )
    ).to eq(
      'id' => 3,
      'publish' => {
        'channel' => 'broadcast:contract',
        'data' => { 'event' => 'message', 'value' => 'contract' }
      }
    )
    expect(described_class.unsubscribe(id: 4, channel: 'broadcast:contract')).to eq(
      'id' => 4,
      'unsubscribe' => { 'channel' => 'broadcast:contract' }
    )
  end

  it 'writes newline-delimited frames with monotonic IDs and correlates replies' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => { 'accepted' => true }))
      end
      protocol = described_class.new(socket: socket, task: task)

      results = [
        protocol.connect(token: 'access'),
        protocol.subscribe(channel: 'broadcast:contract'),
        protocol.publish(
          channel: 'broadcast:contract',
          data: { 'event' => 'message', 'value' => 'contract' }
        ),
        protocol.unsubscribe(channel: 'broadcast:contract')
      ]

      expect(results).to all(eq('accepted' => true))
      expect(socket.writes).to all(end_with("\n"))
      expect(socket.writes.map { |frame| JSON.parse(frame).fetch('id') }).to eq([1, 2, 3, 4])
      protocol.close
    end.wait
  end

  it 'dispatches project-prefixed raw publications by data event' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {}))
      end
      protocol = described_class.new(socket: socket, task: task)
      publication = Async::Condition.new
      protocol.on_publication('broadcast:contract') do |event, data|
        publication.signal([event, data])
      end

      protocol.connect(token: 'access')
      protocol.subscribe(channel: 'broadcast:contract')
      socket.receive(
        JSON.generate(
          'push' => {
            'channel' => 'project-id:broadcast:contract',
            'pub' => { 'data' => { 'event' => 'message', 'value' => 'contract' } }
          }
        )
      )

      expect(publication.wait).to eq(
        ['message', { 'event' => 'message', 'value' => 'contract' }]
      )
      protocol.close
    end.wait
  end

  it 'retains replies that arrive while the socket write yields' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => { 'accepted' => true }))
        Async::Task.current.yield
      end
      protocol = described_class.new(socket: socket, task: task)

      result = task.with_timeout(0.1) { protocol.connect(token: 'access') }

      expect(result).to eq('accepted' => true)
      protocol.close
    end.wait
  end

  it 'propagates server errors to the matching request' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'error' => { 'code' => 107, 'message' => 'bad request' }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task)

      expect { protocol.connect(token: 'bad') }.to raise_error(
        Volcano::Realtime::ServerError,
        'bad request'
      ) { |error| expect(error.code).to eq(107) }
      protocol.close
    end.wait
  end

  it 'rejects pending and future operations when the socket closes' do
    Async do |task|
      socket = FakeSocket.new
      written = Async::Queue.new
      socket.on_write = ->(_command) { written.enqueue(true) }
      protocol = described_class.new(socket: socket, task: task)
      pending = task.async { protocol.connect(token: 'access') }
      written.dequeue
      socket.finish

      expect { pending.wait }.to raise_error(Volcano::Realtime::ClosedError)
      expect { protocol.publish(channel: 'broadcast:contract', data: {}) }.to raise_error(
        Volcano::Realtime::ClosedError
      )
    end.wait
  end
end
