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
