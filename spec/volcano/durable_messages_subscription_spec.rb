# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'spec_helper'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::DurableMessages do
  let(:transport) { SpecSupport::DurableMessagesTransport.new }
  let(:sockets) { Array.new(3) { SpecSupport::FacadeSocket.new } }
  let(:client) do
    remaining = sockets.dup
    Volcano::Client.new(
      anon_key: 'anon-key', _transport: transport,
      _realtime_socket_factory: ->(_address) { remaining.shift },
      _realtime_reconnect_delay: ->(_attempt) { 0 }
    ).tap { |value| value.auth.sign_in(email: 'user@example.com', password: 'secret') }
  end
  let(:messages) { client.durable.messages }
  let(:received) { [] }

  def published(seq, direction: 'out')
    {
      'id' => "message-#{seq}", 'execution_id' => 'execution-1', 'direction' => direction, 'seq' => seq,
      'name' => 'progress', 'data' => { 'seq' => seq }, 'sender' => { 'type' => 'execution', 'user_id' => nil },
      'status' => 'published', 'delivered_at' => nil, 'sent_at' => '2026-10-12T09:00:00Z'
    }
  end

  def page(*seqs, has_more: false)
    { 'data' => seqs.map { |seq| published(seq) }, 'has_more' => has_more }
  end

  def unavailable
    Volcano::Transport::Response.new(status: 503, body: { 'error' => 'unavailable' }, headers: {}, data: nil)
  end

  def publish(socket, data)
    socket.publication(channel: 'project-1:durable:execution-1', data: data)
  end

  def follow(**options, &handler)
    handler ||= ->(message) { received << message.seq }
    messages.subscribe('approvals', 'execution-1', **options, &handler)
  end

  def wait_until(task)
    task.with_timeout(0.5) { task.yield until yield }
  end

  def commands(socket, kind)
    socket.commands.filter_map { |command| command[kind] }
  end

  def lose_connection(task, from:, to:)
    count = transport.lists.size
    from.fail_read(IOError.new('socket failed'))
    wait_until(task) { commands(to, 'subscribe').any? && transport.lists.size > count }
  end

  it 'delivers what was published before it subscribed, then live messages, once each', :aggregate_failures do
    Async do |task|
      transport.pages.enqueue(page(1, 2))
      follow(client_token: 'client-token')

      expect(received).to eq([1, 2])
      [2, 3, 1, 4].each { |seq| publish(sockets[0], published(seq)) }
      wait_until(task) { received.size == 4 }
      expect(received).to eq([1, 2, 3, 4])
      expect(commands(sockets[0], 'subscribe')).to eq(
        [{ 'channel' => 'durable:execution-1', 'data' => { 'client_token' => 'client-token' } }]
      )
      expect(transport.lists.first.except(:target)).to eq(
        authorization: 'access-token', query: { direction: 'out', after: 0 }
      )
      expect(transport.lists.first.fetch(:target).client_token).to eq('client-token')
      expect(transport.list_threads).not_to include(Thread.current)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'follows on the project route without subscribe data when there is no client token' do
    Async do
      transport.pages.enqueue(page)
      follow(project_id: 'project-1')

      expect(commands(sockets[0], 'subscribe')).to eq([{ 'channel' => 'durable:execution-1' }])
      expect(transport.lists.first.fetch(:target).project_id).to eq('project-1')
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'holds messages published during the catch-up and releases them in order' do
    Async do |task|
      subscribing = task.async { follow }
      wait_until(task) { transport.lists.any? }
      [4, 2, 3].each { |seq| publish(sockets[0], published(seq)) }
      task.sleep(0.01)

      expect(received).to be_empty
      transport.pages.enqueue(page(1, 2))
      subscribing.wait
      expect(received).to eq([1, 2, 3, 4])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads every page, and stops at an empty one' do
    Async do
      [page(1, 2, has_more: true), page(3, has_more: true), page(has_more: true)].each do |next_page|
        transport.pages.enqueue(next_page)
      end
      follow

      expect(received).to eq([1, 2, 3])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 2, 3])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'stops at a page that delivers nothing new', :aggregate_failures do
    Async do
      [page(1, has_more: true), page(1, has_more: true), page(2)].each do |next_page|
        transport.pages.enqueue(next_page)
      end
      follow

      expect(received).to eq([1])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads back what a broadcast shows was missed before delivering it', :aggregate_failures do
    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      wait_until(task) { transport.lists.size == 2 }

      expect(received).to eq([1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { received.size == 3 }
      publish(sockets[0], published(2).merge('prev_seq' => 1))
      publish(sockets[0], published(4).merge('prev_seq' => 3))
      publish(sockets[0], published(5).merge('prev_seq' => '9'))
      publish(sockets[0], published(6).merge('prev_seq' => true))
      publish(sockets[0], published(7))
      wait_until(task) { received.size == 7 }
      expect(received).to eq([1, 2, 3, 4, 5, 6, 7])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'holds a broadcast after a gap until a retry reads what it missed', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.01)
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      transport.pages.enqueue(unavailable)
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      publish(sockets[0], published(4).merge('prev_seq' => 3))
      wait_until(task) { errors.include?('unavailable') }

      expect(received).to eq([1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { received.size == 4 }
      expect(received).to eq([1, 2, 3, 4])
      expect(errors).to eq(['unavailable'])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1, 1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'holds a broadcast without prev_seq while another waits behind a gap', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.05)
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      transport.pages.enqueue(unavailable)
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      wait_until(task) { errors.include?('unavailable') }
      publish(sockets[0], published(4))
      task.sleep(0.01)

      expect(received).to eq([1])
      transport.pages.enqueue(page(2, 3, 4))
      wait_until(task) { received.size == 4 }
      expect(received).to eq([1, 2, 3, 4])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'releases what follows on from a failed read and holds the rest', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 60)
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      lose_connection(task, from: sockets[0], to: sockets[1])
      publish(sockets[1], published(2).merge('prev_seq' => 1))
      publish(sockets[1], published(4).merge('prev_seq' => 3))
      task.sleep(0.01)

      expect(received).to eq([1])
      transport.pages.enqueue(unavailable)
      wait_until(task) { errors.include?('unavailable') }
      expect(received).to eq([1, 2])
      expect(errors).to eq(['socket failed', 'unavailable'])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads again when a read stops short of what a held broadcast follows', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.01)

    Async do |task|
      subscribing = task.async { follow }
      wait_until(task) { transport.lists.any? }
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      task.sleep(0.01)
      transport.pages.enqueue(page(1))
      subscribing.wait

      expect(received).to eq([1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { received.size == 3 }
      expect(received).to eq([1, 2, 3])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'drops a waiting retry once a reconnect catches up', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.2)
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      transport.pages.enqueue(unavailable)
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      wait_until(task) { errors.include?('unavailable') }
      lose_connection(task, from: sockets[0], to: sockets[1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { received.size == 3 }
      task.sleep(0.4)

      expect(received).to eq([1, 2, 3])
      expect(transport.lists.size).to eq(3)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'resumes after the message a handler raised on in a later read', :aggregate_failures do
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.01)
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow do |message|
        received << message.seq
        raise 'handler failed' if message.seq == 2
      end
      transport.pages.enqueue(page(2, 3, 4))
      publish(sockets[0], published(5).merge('prev_seq' => 4))
      wait_until(task) { errors.include?('handler failed') }
      transport.pages.enqueue(page(3, 4, 5))
      wait_until(task) { received.size == 5 }

      expect(received).to eq([1, 2, 3, 4, 5])
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1, 2])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads back a message the connection had no room for', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    entered = Async::Queue.new
    resume = Async::Queue.new

    Async do |task|
      transport.pages.enqueue(page(1))
      follow do |message|
        received << message.seq
        next unless message.seq == 2

        entered.enqueue(true)
        resume.dequeue
      end
      publish(sockets[0], published(2).merge('prev_seq' => 1))
      task.with_timeout(0.5) { entered.dequeue }
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      publish(sockets[0], published(4).merge('prev_seq' => 3))
      wait_until(task) { transport.lists.size == 2 }
      resume.enqueue(true)
      task.sleep(0.01)

      expect(received).to eq([1, 2])
      transport.pages.enqueue(page(3, 4))
      wait_until(task) { received.size == 4 }
      expect(received).to eq([1, 2, 3, 4])
      expect(transport.lists.last.fetch(:query)).to eq(direction: 'out', after: 2)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'calls the block for a read only once its call on a live message returns', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    calls = []
    entered = Async::Queue.new
    resume = Async::Queue.new

    Async do |task|
      transport.pages.enqueue(page(1))
      follow do |message|
        calls << [:start, message.seq]
        if message.seq == 2
          entered.enqueue(true)
          resume.dequeue
        end
        calls << [:end, message.seq]
      end
      publish(sockets[0], published(2).merge('prev_seq' => 1))
      task.with_timeout(0.5) { entered.dequeue }
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      publish(sockets[0], published(4).merge('prev_seq' => 3))
      transport.pages.enqueue(page(3, 4))
      wait_until(task) { transport.lists.size == 2 }
      task.sleep(0.01)

      expect(calls).to eq([[:start, 1], [:end, 1], [:start, 2]])
      resume.enqueue(true)
      wait_until(task) { calls.size == 8 }
      expect(calls.drop(2)).to eq([[:start, 2], [:end, 2], [:start, 3], [:end, 3], [:start, 4], [:end, 4]])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads once for a burst of publications the connection had no room for' do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1)
    entered = Async::Queue.new
    resume = Async::Queue.new

    Async do |task|
      transport.pages.enqueue(page(1))
      follow do |message|
        received << message.seq
        next unless message.seq == 2

        entered.enqueue(true)
        resume.dequeue
      end
      publish(sockets[0], published(2).merge('prev_seq' => 1))
      task.with_timeout(0.5) { entered.dequeue }
      (3..8).each { |seq| publish(sockets[0], published(seq).merge('prev_seq' => seq - 1)) }
      wait_until(task) { transport.lists.size == 2 }
      transport.pages.enqueue(page(3, 4, 5, 6, 7, 8))
      transport.pages.enqueue(page)
      resume.enqueue(true)
      wait_until(task) { received.size == 8 }
      task.sleep(0.05)

      expect(transport.lists.size).to be <= 3
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reports a block that raises on a live message and goes on delivering', :aggregate_failures do
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page)
      follow do |message|
        received << message.seq
        raise 'handler failed' if message.seq == 1
      end
      publish(sockets[0], published(1))
      publish(sockets[0], published(2))
      wait_until(task) { received.size == 2 }

      expect(received).to eq([1, 2])
      expect(errors).to eq(['handler failed'])
      expect(transport.lists.size).to eq(1)
    ensure
      client.realtime.disconnect
    end.wait
  end

  %i[remove_all_channels disconnect].each do |ending|
    it "delivers nothing a pending read returns once #{ending} ends the subscription", :aggregate_failures do
      Async do |task|
        transport.pages.enqueue(page(1))
        follow
        publish(sockets[0], published(3).merge('prev_seq' => 2))
        wait_until(task) { transport.lists.size == 2 }
        client.realtime.public_send(ending)
        transport.pages.enqueue(page(2, 3))
        task.sleep(0.01)

        expect(received).to eq([1])
        expect(transport.lists.size).to eq(2)
      ensure
        client.realtime.disconnect
      end.wait
    end
  end

  def other_session
    Volcano::Session.new(access_token: 'other-access-token', refresh_token: 'other-refresh-token', user_id: 'user-456')
  end

  { 'another session replaces it' => true, 'it signs out' => false }.each do |change, replaced|
    it "delivers nothing a pending read returns once #{change}", :aggregate_failures do
      errors = []
      client.realtime.on_error { |context| errors << context.message }

      Async do |task|
        transport.pages.enqueue(page(1))
        follow
        publish(sockets[0], published(3).merge('prev_seq' => 2))
        wait_until(task) { transport.lists.size == 2 }
        client.store_session(replaced ? other_session : nil)
        transport.pages.enqueue(page(2, 3))
        wait_until(task) { errors.any? }

        expect(received).to eq([1])
        expect(errors).to contain_exactly(/session that subscribed/)
        expect(transport.lists.size).to eq(2)
      ensure
        client.realtime.disconnect
      end.wait
    end
  end

  it 'reads nothing more once the session changes', :aggregate_failures do
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      client.store_session(other_session)
      publish(sockets[0], published(3).merge('prev_seq' => 2))
      wait_until(task) { errors.any? }

      expect(errors).to contain_exactly(/session that subscribed/)
      expect(transport.lists.size).to eq(1)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'delivers no live message once the session changes', :aggregate_failures do
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page)
      follow
      client.store_session(other_session)
      publish(sockets[0], published(1))
      publish(sockets[0], published(2))
      wait_until(task) { errors.any? }
      task.sleep(0.01)

      expect(received).to be_empty
      expect(errors).to contain_exactly(/session that subscribed/)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'keeps delivering after a token refresh' do
    Async do |task|
      transport.pages.enqueue(page)
      follow
      client.store_session(
        Volcano::Session.new(access_token: 'access-refreshed', refresh_token: 'refresh-token', user_id: 'user-123'),
        event: :token_refreshed
      )
      publish(sockets[0], published(1))
      wait_until(task) { received.any? }

      expect(received).to eq([1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'fails subscribing when the session changes during the first read', :aggregate_failures do
    Async do |task|
      subscribing = task.async { follow }
      wait_until(task) { transport.lists.any? }
      client.store_session(other_session)
      transport.pages.enqueue(page(1))

      expect { subscribing.wait }.to raise_error(Volcano::Error::SessionChangedError, /session that subscribed/)
      expect(received).to be_empty
      expect(commands(sockets[0], 'unsubscribe')).to eq([{ 'channel' => 'durable:execution-1' }])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'ignores publications that are not messages the execution published' do
    Async do |task|
      transport.pages.enqueue(page)
      follow
      publish(sockets[0], published(1, direction: 'in'))
      publish(sockets[0], { 'seq' => 2 })
      publish(sockets[0], published(3))

      wait_until(task) { received.any? }
      expect(received).to eq([3])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reads back what a reconnect missed before live delivery resumes', :aggregate_failures do
    Async do |task|
      transport.pages.enqueue(page(1))
      follow(client_token: 'client-token')
      lose_connection(task, from: sockets[0], to: sockets[1])
      publish(sockets[1], published(4))
      task.sleep(0.01)

      expect(received).to eq([1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { received.size == 4 }
      expect(received).to eq([1, 2, 3, 4])
      expect(commands(sockets[1], 'subscribe').first.fetch('data')).to eq('client_token' => 'client-token')
      expect(transport.lists.last.fetch(:query)).to eq(direction: 'out', after: 1)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'releases held messages only after the last of overlapping catch-ups' do
    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      lose_connection(task, from: sockets[0], to: sockets[1])
      sockets[1].fail_read(IOError.new('socket failed'))
      wait_until(task) { commands(sockets[2], 'subscribe').any? }
      publish(sockets[2], published(5))
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { transport.lists.size == 3 }

      expect(received).to eq([1, 2, 3])
      transport.pages.enqueue(page(4))
      wait_until(task) { received.size == 5 }
      expect(received).to eq([1, 2, 3, 4, 5])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'reports a catch-up that fails after a reconnect and goes on delivering live', :aggregate_failures do
    errors = []
    client.realtime.on_error { |context| errors << context.message }

    Async do |task|
      transport.pages.enqueue(page(1))
      follow
      lose_connection(task, from: sockets[0], to: sockets[1])
      publish(sockets[1], published(3))
      task.sleep(0.01)
      transport.pages.enqueue(unavailable)

      wait_until(task) { errors.include?('unavailable') }
      expect(errors).to eq(['socket failed', 'unavailable'])
      expect(received).to eq([1, 3])
      publish(sockets[1], published(4))
      wait_until(task) { received.size == 3 }
      expect(received).to eq([1, 3, 4])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'stops delivering when the handler unsubscribes', :aggregate_failures do
    Async do |task|
      transport.pages.enqueue(page(1))
      subscription = nil
      subscription = follow do |message|
        received << message.seq
        subscription&.unsubscribe if message.seq == 2
      end
      lose_connection(task, from: sockets[0], to: sockets[1])
      transport.pages.enqueue(page(2, 3))
      wait_until(task) { commands(sockets[1], 'unsubscribe').any? }

      expect(received).to eq([1, 2])
      expect(commands(sockets[1], 'unsubscribe')).to eq([{ 'channel' => 'durable:execution-1' }])
      expect(subscription.unsubscribe).to be_nil
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'refuses a second subscription to an execution until the first one ends', :aggregate_failures do
    Async do |task|
      transport.pages.enqueue(page(1))
      first = follow

      expect { follow }.to raise_error(Volcano::Realtime::DuplicateSubscriptionError, /already subscribed/)
      first.unsubscribe
      transport.pages.enqueue(page(1))
      follow
      first.unsubscribe
      publish(sockets[0], published(2))
      wait_until(task) { received.size == 3 }
      expect(received).to eq([1, 1, 2])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'leaves the channel when the first catch-up fails', :aggregate_failures do
    Async do
      transport.pages.enqueue(unavailable)

      expect { follow }.to raise_error(Volcano::Error::VolcanoError, 'unavailable')
      expect(commands(sockets[0], 'unsubscribe')).to eq([{ 'channel' => 'durable:execution-1' }])
      transport.pages.enqueue(page(1))
      follow
      expect(received).to eq([1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'raises the error the handler raised during the catch-up' do
    Async do
      transport.pages.enqueue(page(1))

      expect { follow { raise 'handler failed' } }.to raise_error(RuntimeError, 'handler failed')
      expect(commands(sockets[0], 'unsubscribe').size).to eq(1)
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'calls the block for nothing it held once the block raises during the first read', :aggregate_failures do
    Async do |task|
      subscribing = task.async do
        follow do |message|
          received << message.seq
          raise 'handler failed'
        end
      end
      wait_until(task) { transport.lists.any? }
      publish(sockets[0], published(2).merge('prev_seq' => 1))
      task.sleep(0.01)
      transport.pages.enqueue(page(1))

      expect { subscribing.wait }.to raise_error(RuntimeError, 'handler failed')
      expect(received).to eq([1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'calls the block for nothing it held once the first read fails', :aggregate_failures do
    Async do |task|
      subscribing = task.async { follow }
      wait_until(task) { transport.lists.any? }
      publish(sockets[0], published(1).merge('prev_seq' => 0))
      task.sleep(0.01)
      transport.pages.enqueue(unavailable)

      expect { subscribing.wait }.to raise_error(Volcano::Error::VolcanoError, 'unavailable')
      expect(received).to be_empty
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'drops the oldest of more than 128 held messages for a read to list', :aggregate_failures do
    stub_const('Volcano::Realtime::Protocol::DEFAULT_MAX_CALLBACK_QUEUE', 1000)
    stub_const('Volcano::DurableMessageCatchUps::FIRST_RETRY_SECONDS', 0.01)

    Async do |task|
      subscribing = task.async { follow }
      wait_until(task) { transport.lists.any? }
      [130, *2..129].each { |seq| publish(sockets[0], published(seq).merge('prev_seq' => seq - 1)) }
      task.sleep(0.05)
      transport.pages.enqueue(page(1))
      subscribing.wait

      expect(received).to eq([1])
      transport.pages.enqueue(page(2))
      wait_until(task) { received.size == 130 }
      expect(received).to eq((1..130).to_a)
      expect(transport.lists.map { |list| list.fetch(:query).fetch(:after) }).to eq([0, 1])
    ensure
      client.realtime.disconnect
    end.wait
  end

  it 'unsubscribes quietly once the connection is closed' do
    Async do
      transport.pages.enqueue(page)
      subscription = follow
      client.realtime.disconnect

      expect(subscription.unsubscribe).to be_nil
      expect(commands(sockets[0], 'unsubscribe')).to be_empty
    end.wait
  end

  it 'refuses to follow once the connection is closed' do
    Async do
      client.realtime.disconnect

      expect { follow }.to raise_error(Volcano::Realtime::ClosedError)
    end.wait
  end

  it 'requires a signed-in session' do
    signed_out = Volcano::Client.new(anon_key: 'anon-key', _transport: transport,
                                     _realtime_socket_factory: ->(_address) { sockets[0] })

    Async do
      expect { signed_out.durable.messages.subscribe('approvals', 'execution-1') { nil } }
        .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
      expect(transport.lists).to be_empty
    end.wait
  end

  it 'requires a block' do
    expect { messages.subscribe('approvals', 'execution-1') }
      .to raise_error(ArgumentError, 'subscribe requires a block')
  end
end
