# frozen_string_literal: true

require 'async'
require 'async/condition'
require 'async/queue'
require 'json'
require 'spec_helper'

RSpec.describe Volcano::Realtime.const_get(:Protocol, false) do
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
    expect(described_class.presence(id: 5, channel: 'presence:lobby')).to eq(
      'id' => 5,
      'presence' => { 'channel' => 'presence:lobby' }
    )
  end

  it 'builds a recoverable presence subscription command' do
    expect(
      described_class.subscribe(
        id: 1,
        channel: 'presence:lobby',
        recoverable: true,
        join_leave: true
      )
    ).to eq(
      'id' => 1,
      'subscribe' => {
        'channel' => 'presence:lobby',
        'recoverable' => true,
        'join_leave' => true
      }
    )
  end

  it 'builds an initial recovery subscription command' do
    command = described_class.subscribe(
      id: 7, channel: 'broadcast:contract', recovery: {}
    )

    expect(command).to eq(
      'id' => 7,
      'subscribe' => {
        'channel' => 'broadcast:contract',
        'recover' => true,
        'positioned' => true,
        'recoverable' => true
      }
    )
  end

  it 'builds a recovery subscription command from a stream position' do
    command = described_class.subscribe(
      id: 7,
      channel: 'broadcast:contract',
      recovery: { epoch: 'epoch-1', offset: 42 }
    )

    expect(command.fetch('subscribe')).to include(
      'recover' => true,
      'epoch' => 'epoch-1',
      'offset' => 42,
      'positioned' => true,
      'recoverable' => true
    )
  end

  it 'returns presence command results' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {
                                       'presence' => { 'client-1' => { 'client' => 'client-1' } }
                                     }))
      end
      protocol = described_class.new(socket: socket, task: task)

      expect(protocol.presence(channel: 'presence:lobby')).to eq(
        'presence' => { 'client-1' => { 'client' => 'client-1' } }
      )
      protocol.close
    end.wait
  end

  it 'dispatches project-prefixed join and leave pushes' do
    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task)
      events = Async::Queue.new
      protocol.on_presence('presence:lobby') { |event, info| events.enqueue([event, info]) }
      info = { 'client' => 'client-1', 'user' => 'user-1', 'conn_info' => { 'status' => 'online' } }

      %w[join leave].each do |event|
        socket.receive(JSON.generate('push' => {
                                       'channel' => 'project-id:presence:lobby',
                                       event => { 'info' => info }
                                     }))
      end

      expect(task.with_timeout(0.2) { [events.dequeue, events.dequeue] }).to eq(
        [['join', info], ['leave', info]]
      )
      protocol.close
    end.wait
  end

  it 'requests a presence resync when join and leave pushes overflow the callback queue' do
    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      entered = Async::Queue.new
      release = Async::Queue.new
      events = Async::Queue.new
      protocol.on_presence('presence:lobby') do |event, info|
        entered.enqueue(true) if event == 'join' && info['client'] == 'client-1'
        release.dequeue if event == 'join' && info['client'] == 'client-1'
        events.enqueue(event)
      end

      push = lambda do |client|
        JSON.generate('push' => {
                        'channel' => 'project:presence:lobby',
                        'join' => { 'info' => { 'client' => client } }
                      })
      end
      socket.receive(push.call('client-1'))
      entered.dequeue
      socket.receive(push.call('client-2'), push.call('client-3'))
      release.enqueue(true)

      received = task.with_timeout(0.2) { [events.dequeue, events.dequeue, events.dequeue] }
      expect(received).to eq(%w[join join sync_required])
      protocol.close
    end.wait
  end

  it 'correlates distinct concurrent replies that arrive in reverse ID order' do
    Async do |task|
      socket = FakeSocket.new
      written = Async::Queue.new
      socket.on_write = ->(command) { written.enqueue(command) }
      protocol = described_class.new(socket: socket, task: task)

      first = task.async { protocol.connect(token: 'access') }
      second = task.async do
        protocol.publish(
          channel: 'broadcast:contract',
          data: { 'event' => 'message', 'value' => 'second' }
        )
      end
      commands = [written.dequeue, written.dequeue]
      socket.receive(
        JSON.generate('id' => commands.fetch(1).fetch('id'), 'result' => { 'caller' => 'second' }),
        JSON.generate('id' => commands.fetch(0).fetch('id'), 'result' => { 'caller' => 'first' })
      )

      expect(task.with_timeout(0.2) { first.wait }).to eq('caller' => 'first')
      expect(task.with_timeout(0.2) { second.wait }).to eq('caller' => 'second')
      expect(socket.writes).to all(end_with("\n"))
      expect(socket.writes.map { |frame| JSON.parse(frame).fetch('id') }).to eq([1, 2])
      protocol.close
    end.wait
  end

  it 'serializes concurrent subscription state changes for one channel' do
    Async do |task|
      socket = FakeSocket.new
      entered = Async::Queue.new
      release = Async::Queue.new
      blocked = false
      socket.on_write = lambda do |command|
        if command.key?('subscribe') && !blocked
          blocked = true
          entered.enqueue(true)
          release.dequeue
        end
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {}))
      end
      protocol = described_class.new(socket: socket, task: task)
      first = task.async { protocol.subscribe(channel: 'broadcast:contract') }
      entered.dequeue
      second = task.async do
        protocol.subscribe(channel: 'broadcast:contract')
      rescue StandardError => e
        e
      end
      task.yield
      release.enqueue(true)

      expect(task.with_timeout(0.2) { first.wait }).to eq({})
      expect(task.with_timeout(0.2) { second.wait }).to be_a(
        Volcano::Realtime::DuplicateSubscriptionError
      )
      expect(socket.writes.count { |frame| JSON.parse(frame).key?('subscribe') }).to eq(1)
      protocol.close
    end.wait
  end

  it 'waits for an in-flight protocol subscription before unsubscribing' do
    Async do |task|
      socket = FakeSocket.new
      entered = Async::Queue.new
      release = Async::Queue.new
      socket.on_write = lambda do |command|
        if command.key?('subscribe')
          entered.enqueue(true)
          release.dequeue
        end
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {}))
      end
      protocol = described_class.new(socket: socket, task: task)
      subscribing = task.async { protocol.subscribe(channel: 'broadcast:contract') }
      entered.dequeue
      unsubscribe_finished = false
      unsubscribing = task.async do
        protocol.unsubscribe(channel: 'broadcast:contract')
        unsubscribe_finished = true
      end
      task.yield
      finished_before_subscribe = unsubscribe_finished
      release.enqueue(true)

      task.with_timeout(0.2) { subscribing.wait }
      task.with_timeout(0.2) { unsubscribing.wait }
      expect(finished_before_subscribe).to be(false)
      expect(socket.writes.map { |frame| JSON.parse(frame).keys.fetch(1) }).to eq(
        %w[subscribe unsubscribe]
      )
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

  it 'dispatches recovered publications before a same-frame live push' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        next unless command.key?('subscribe')

        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => {
              'epoch' => 'epoch-1',
              'offset' => 3,
              'publications' => [
                { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 'recovered-2' } },
                { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 'recovered-3' } }
              ]
            }
          ),
          JSON.generate(
            'push' => {
              'channel' => 'broadcast:contract',
              'pub' => { 'offset' => 4, 'data' => { 'event' => 'message', 'value' => 'live-4' } }
            }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task)
      received = []
      protocol.on_publication('broadcast:contract') do |_event, data, publication = nil, recovered: false|
        received << [data.fetch('value'), publication&.fetch('offset'), recovered]
      end

      protocol.subscribe(channel: 'broadcast:contract', recovery: { epoch: 'epoch-1', offset: 1 })
      task.with_timeout(0.2) { task.yield until received.any? }

      expect(received).to eq(
        [
          ['recovered-2', 2, true],
          ['recovered-3', 3, true],
          ['live-4', 4, false]
        ]
      )
      protocol.close
    end.wait
  end

  it 'keeps command replies flowing while retained publications backpressure callbacks' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        if command.key?('subscribe')
          reply = JSON.generate(
            'id' => command.fetch('id'),
            'result' => {
              'epoch' => 'epoch-1',
              'offset' => 3,
              'publications' => [
                { 'offset' => 1, 'data' => { 'event' => 'message', 'value' => 1 } },
                { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } },
                { 'offset' => 3, 'data' => { 'event' => 'message', 'value' => 3 } }
              ]
            }
          )
          live = JSON.generate(
            'push' => {
              'channel' => 'broadcast:contract',
              'pub' => {
                'offset' => 4,
                'data' => { 'event' => 'message', 'value' => 4 }
              }
            }
          )
          socket.receive_raw("#{reply}\n#{live}")
        else
          socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {}))
        end
      end
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      command_completed = Async::Queue.new
      received = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data|
        value = data.fetch('value')
        if value == 1
          protocol.publish(channel: 'broadcast:contract', data: { 'event' => 'callback-command' })
          command_completed.enqueue(true)
        end
        received.enqueue(value)
      end

      subscription = task.async do
        protocol.subscribe(channel: 'broadcast:contract', recovery: {})
      end

      begin
        expect(task.with_timeout(0.2) { command_completed.dequeue }).to be(true)
        expect(task.with_timeout(0.2) { subscription.wait }).to include(
          'epoch' => 'epoch-1', 'offset' => 3
        )
        expect(task.with_timeout(0.2) { Array.new(3) { received.dequeue } }).to eq([1, 2, 3])
      ensure
        protocol.close
      end
    end.wait
  end

  it 'does not advance past a dropped live publication' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => { 'epoch' => 'epoch-1', 'offset' => 0, 'publications' => [] }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      entered = Async::Queue.new
      release = Async::Queue.new
      received = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data, publication|
        protocol.complete_publication('broadcast:contract', publication)
        entered.enqueue(true) if data.fetch('value') == 1
        release.dequeue if data.fetch('value') == 1
        received.enqueue(data.fetch('value'))
      end
      protocol.subscribe(channel: 'broadcast:contract', recovery: {})

      publication = lambda do |offset|
        JSON.generate(
          'push' => {
            'channel' => 'broadcast:contract',
            'pub' => { 'offset' => offset, 'data' => { 'event' => 'message', 'value' => offset } }
          }
        )
      end
      socket.receive(publication.call(1))
      entered.dequeue
      socket.receive(publication.call(2), publication.call(3))
      release.enqueue(true)
      expect(task.with_timeout(0.2) { [received.dequeue, received.dequeue] }).to eq([1, 2])

      socket.receive(publication.call(4))
      expect(task.with_timeout(0.2) { received.dequeue }).to eq(4)
      expect(protocol.position('broadcast:contract')).to eq(
        epoch: 'epoch-1', offset: 2
      )
      protocol.close
    end.wait
  end

  it 'does not advance a recovery cursor across an epoch gap' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => { 'epoch' => 'epoch-1', 'offset' => 0, 'publications' => [] }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task)

      begin
        protocol.subscribe(channel: 'broadcast:contract', recovery: {})
        protocol.drop_publication('broadcast:contract', 'epoch' => 'epoch-1', 'offset' => 1)
        protocol.complete_publication('broadcast:contract', 'epoch' => 'epoch-2', 'offset' => 2)

        expect(protocol.position('broadcast:contract')).to eq(
          epoch: 'epoch-1', offset: 0
        )
      ensure
        protocol.close
      end
    end.wait
  end

  it 'does not advance after admitted publication metadata is malformed' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => { 'epoch' => 'epoch-1', 'offset' => 0, 'publications' => [] }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task)
      received = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data, publication|
        protocol.complete_publication('broadcast:contract', publication)
        received.enqueue(data.fetch('value'))
      end

      publication = lambda do |offset, value|
        JSON.generate(
          'push' => {
            'channel' => 'broadcast:contract',
            'pub' => {
              'epoch' => 'epoch-1', 'offset' => offset,
              'data' => { 'event' => 'message', 'value' => value }
            }
          }
        )
      end

      begin
        protocol.subscribe(channel: 'broadcast:contract', recovery: {})
        socket.receive(publication.call('malformed', 1), publication.call(2, 2))
        expect(task.with_timeout(0.2) { [received.dequeue, received.dequeue] }).to eq([1, 2])
        expect(protocol.position('broadcast:contract')).to eq(epoch: 'epoch-1', offset: 0)
      ensure
        protocol.close
      end
    end.wait
  end

  it 'delivers retained publications despite live callback queue pressure' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => {
              'epoch' => 'epoch-1',
              'offset' => 2,
              'publications' => [
                { 'offset' => 1, 'data' => { 'event' => 'message', 'value' => 1 } },
                { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 2 } }
              ]
            }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      entered = Async::Queue.new
      release = Async::Queue.new
      received = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data|
        entered.enqueue(true) if data.fetch('value') == 1
        release.dequeue if data.fetch('value') == 1
        received.enqueue(data.fetch('value'))
      end

      begin
        protocol.subscribe(channel: 'broadcast:contract', recovery: {})
        entered.dequeue
        release.enqueue(true)

        expect(task.with_timeout(0.2) { [received.dequeue, received.dequeue] }).to eq([1, 2])
      ensure
        protocol.close
      end
    end.wait
  end

  it 'queues retained publications behind callback work without blocking subscribe' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        next unless command.key?('subscribe')

        socket.receive(
          JSON.generate(
            'id' => command.fetch('id'),
            'result' => {
              'epoch' => 'epoch-1',
              'offset' => 2,
              'publications' => [
                { 'offset' => 1, 'data' => { 'event' => 'message', 'value' => 'recovered-1' } },
                { 'offset' => 2, 'data' => { 'event' => 'message', 'value' => 'recovered-2' } }
              ]
            }
          )
        )
      end
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      entered = Async::Queue.new
      release = Async::Queue.new
      received = Async::Queue.new
      subscription_returned = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data|
        value = data.fetch('value')
        entered.enqueue(true) if value == 'live-1'
        release.dequeue if value == 'live-1'
        received.enqueue(value)
      end

      publication = lambda do |value|
        JSON.generate(
          'push' => {
            'channel' => 'broadcast:contract',
            'pub' => { 'data' => { 'event' => 'message', 'value' => value } }
          }
        )
      end
      socket.receive(publication.call('live-1'))
      entered.dequeue
      socket.receive(publication.call('live-2'))
      subscription = task.async do
        protocol.subscribe(channel: 'broadcast:contract', recovery: {})
        subscription_returned.enqueue(true)
      end

      begin
        expect(task.with_timeout(0.2) { subscription_returned.dequeue }).to be(true)

        release.enqueue(true)
        task.with_timeout(0.2) { subscription.wait }
        expect(task.with_timeout(0.2) { Array.new(4) { received.dequeue } }).to eq(
          %w[live-1 live-2 recovered-1 recovered-2]
        )
      ensure
        protocol.close
      end
    end.wait
  end

  [
    [
      'a null retained-publication collection',
      { 'epoch' => 'epoch-1', 'offset' => 1, 'publications' => nil }
    ],
    [
      'a non-array retained-publication collection',
      { 'epoch' => 'epoch-1', 'offset' => 1, 'publications' => { 'offset' => 2 } }
    ],
    [
      'a non-hash retained publication',
      { 'epoch' => 'epoch-1', 'offset' => 1, 'publications' => ['invalid'] }
    ],
    ['a non-object subscription result', 'invalid']
  ].each do |description, result|
    it "keeps the connection usable after #{description}" do
      Async do |task|
        socket = FakeSocket.new
        socket.on_write = lambda do |command|
          reply = command.key?('subscribe') ? result : {}
          socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => reply))
        end
        protocol = described_class.new(socket: socket, task: task)

        expect(protocol.subscribe(channel: 'broadcast:contract', recovery: {})).to eq(result)
        expect(protocol.publish(channel: 'broadcast:contract', data: {})).to eq({})
        protocol.close
      end.wait
    end
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

  it 'answers Centrifuge application pings' do
    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task)

      socket.receive('{}')
      task.with_timeout(0.2) { task.yield until socket.writes.any? }

      expect(socket.writes).to eq(["{}\n"])
      protocol.close
    end.wait
  end

  it 'lets publication callbacks issue commands without blocking the reader' do
    Async do |task|
      socket = FakeSocket.new
      socket.on_write = lambda do |command|
        socket.receive(JSON.generate('id' => command.fetch('id'), 'result' => {}))
      end
      protocol = described_class.new(socket: socket, task: task)
      completed = Async::Condition.new
      protocol.on_publication('broadcast:contract') do
        protocol.publish(channel: 'broadcast:contract', data: { 'event' => 'reply' })
        completed.signal(true)
      end

      socket.receive(
        JSON.generate(
          'push' => {
            'channel' => 'broadcast:contract',
            'pub' => { 'data' => { 'event' => 'message' } }
          }
        )
      )

      expect(task.with_timeout(0.2) { completed.wait }).to be(true)
      protocol.close
    end.wait
  end

  it 'bounds callback work and survives callback failures' do
    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task, max_callback_queue: 1)
      started = Async::Queue.new
      release = Async::Queue.new
      received = Async::Queue.new
      protocol.on_publication('broadcast:contract') do |_event, data|
        value = data.fetch('value')
        if value == 'error'
          started.enqueue(:error)
          raise 'callback failed'
        end

        started.enqueue(true) if value == 'first'
        release.dequeue if value == 'first'
        received.enqueue(value)
      end

      publication = lambda do |value|
        socket.receive(
          JSON.generate(
            'push' => {
              'channel' => 'broadcast:contract',
              'pub' => { 'data' => { 'event' => 'message', 'value' => value } }
            }
          )
        )
      end
      publication.call('first')
      started.dequeue
      socket.receive(
        %w[second dropped].map do |value|
          JSON.generate(
            'push' => {
              'channel' => 'broadcast:contract',
              'pub' => { 'data' => { 'event' => 'message', 'value' => value } }
            }
          )
        end.join("\n")
      )
      release.enqueue(true)

      expect(task.with_timeout(0.2) { received.dequeue }).to eq('first')
      expect(task.with_timeout(0.2) { received.dequeue }).to eq('second')
      publication.call('error')
      expect(task.with_timeout(0.2) { started.dequeue }).to eq(:error)
      publication.call('after-error')
      expect(task.with_timeout(0.2) { received.dequeue }).to eq('after-error')
      protocol.close
    end.wait
  end

  it 'closes the reader and socket when a callback closes the protocol' do
    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task)
      completed = Async::Condition.new
      protocol.on_publication('broadcast:contract') do
        protocol.close
        completed.signal(true)
      end

      socket.receive(
        JSON.generate(
          'push' => {
            'channel' => 'broadcast:contract',
            'pub' => { 'data' => { 'event' => 'message' } }
          }
        )
      )

      expect(task.with_timeout(0.2) { completed.wait }).to be(true)
      expect(socket).to be_closed
    end.wait
  end

  it 'bounds pending commands and times out missing replies' do
    Async do |task|
      socket = FakeSocket.new
      written = Async::Queue.new
      socket.on_write = ->(_command) { written.enqueue(true) }
      protocol = described_class.new(
        socket: socket,
        task: task,
        request_timeout: 0.02,
        max_pending: 1
      )
      pending = task.async { protocol.connect(token: 'access') }
      written.dequeue

      expect do
        protocol.publish(channel: 'broadcast:contract', data: {})
      end.to raise_error(Volcano::Realtime::PendingLimitError)
      expect { pending.wait }.to raise_error(Volcano::Realtime::RequestTimeoutError)
      protocol.close
    end.wait
  end

  it 'closes the socket after an abnormal reader failure' do
    broken_frame = Object.new
    broken_frame.define_singleton_method(:to_str) { raise IOError, 'read failed' }

    Async do |task|
      socket = FakeSocket.new
      protocol = described_class.new(socket: socket, task: task)
      socket.receive_raw(broken_frame)
      task.with_timeout(0.2) { task.yield until socket.closed? }

      expect(socket).to be_closed
      expect do
        protocol.publish(channel: 'broadcast:contract', data: {})
      end.to raise_error(Volcano::Realtime::ClosedError, 'read failed')
    end.wait
  end
end
