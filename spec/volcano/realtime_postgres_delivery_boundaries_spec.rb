# frozen_string_literal: true

require 'async'
require 'async/queue'
require_relative '../support/fake_realtime'

RSpec.describe Volcano::Realtime do
  let(:socket) { SpecSupport::FacadeSocket.new }
  let(:transport) { SpecSupport::RealtimeDatabaseTransport.new([{ 'id' => 1, 'body' => 'fetched' }]) }
  let(:client) do
    instance = Volcano::Client.new(
      anon_key: 'anon-key', _transport: transport, _realtime_socket_factory: ->(_address) { socket }
    )
    instance.auth.sign_in(email: 'user@example.com', password: 'secret')
    instance
  end
  let(:channel) { client.realtime.channel('public:messages', type: :postgres) }
  let(:delivered) { Async::Queue.new }

  around { |example| Async { example.run }.wait }
  after { client.realtime.disconnect }

  [{ 'type' => 'unknown' }, { 'schema' => nil }, { 'table' => 1 }, { 'timestamp' => false },
   { 'record' => [] }, { 'old_record' => [] }, { 'columns' => {} }, { 'mode' => 'unknown' }].each do |fields|
    it "discards malformed changes before a later valid delivery: #{fields.inspect}" do
      channel.on('*') { |change| delivered.enqueue(change.id) }
      channel.subscribe

      publish(change(1).merge(fields))
      publish(change(2))

      expect(wait_for(delivered)).to eq(2)
      expect(delivered).to be_empty
    end
  end

  it 'delivers only to matching filtered listeners alongside an unfiltered listener' do
    filtered = []
    channel.on_postgres_changes('UPDATE', schema: 'other', table: 'messages') { filtered << :schema }
    channel.on_postgres_changes('UPDATE', schema: 'public', table: 'other') { filtered << :table }
    channel.on_postgres_changes('UPDATE', schema: 'public', table: 'messages') { filtered << :matched }
    channel.on('UPDATE') { |change| delivered.enqueue(change.id) }
    channel.subscribe

    publish(change(1))

    expect(wait_for(delivered)).to eq(1)
    expect(filtered).to eq([:matched])
  end

  it 'lets a change callback unsubscribe without deadlocking or emitting a stale wildcard event' do
    unsubscribed = Async::Queue.new
    channel.on('UPDATE') do
      channel.unsubscribe
      unsubscribed.enqueue(true)
    end
    channel.on('*') { |change| delivered.enqueue(change.id) }
    channel.subscribe
    publish(change(1))
    expect(wait_for(unsubscribed)).to be(true)

    channel.subscribe
    publish(change(2).merge('type' => 'INSERT'))

    expect(wait_for(delivered)).to eq(2)
    expect(delivered).to be_empty
  end

  it 'keeps an inline change separate from a pending lightweight fetch' do
    batched = fetching_channel
    batched.subscribe

    publish(change(1).merge('mode' => 'lightweight'))
    publish(change(2).merge('record' => { 'id' => 2, 'body' => 'inline' }))

    results = [wait_for(delivered), wait_for(delivered)]
    expect(results.map(&:record)).to eq([{ 'id' => 1, 'body' => 'fetched' }, { 'id' => 2, 'body' => 'inline' }])
    expect(delivered).to be_empty
    expect(transport.queries.length).to eq(1)
  end

  it 'fetches immediately when the batching deadline has already elapsed' do
    client.realtime.database_name = 'app'
    allow(channel).to receive(:monotonic_time).and_return(100.0, 101.0)
    channel.on('*') { |change| delivered.enqueue(change) }
    channel.subscribe

    publish(change(1).merge('mode' => 'lightweight'))

    expect(wait_for(delivered).record).to eq('id' => 1, 'body' => 'fetched')
    expect(transport.queries.length).to eq(1)
  end

  it 'does not enqueue publications received after unsubscribe' do
    channel.on('*') { |change| delivered.enqueue(change.id) }
    channel.subscribe
    channel.unsubscribe
    sentinel = client.realtime.channel('sentinel').on('message') { delivered.enqueue(:finished) }
    sentinel.subscribe

    publish(change(1))
    socket.publication(channel: sentinel.name, data: { 'event' => 'message' })

    expect(wait_for(delivered)).to eq(:finished)
    expect(delivered).to be_empty
    expect(transport.queries).to be_empty
  end

  it 'discards a batch when the user changes before the fetch starts' do
    completed = pending_batch
    client.auth.current_session = Volcano::Session.new(
      access_token: 'other-access', refresh_token: 'other-refresh', user_id: 'other-user'
    )

    publish(change(2))
    2.times { expect(wait_for(completed)).to be(true) }

    expect(delivered).to be_empty
    expect(transport.queries).to be_empty
  end

  private

  def fetching_channel
    client.realtime.database_name = 'app'
    client.realtime.channel('public:messages', type: :postgres, fetch_batch_window_ms: 10_000)
          .on('*') { |change| delivered.enqueue(change) }
  end

  def pending_batch
    batched = fetching_channel
    started = Async::Queue.new
    completed = Async::Queue.new
    observe_batches(batched, started, completed)
    batched.subscribe
    publish(change(1).merge('mode' => 'lightweight'))
    wait_for(started)
    completed
  end

  def observe_batches(batched, started, completed)
    allow(batched).to receive(:collect_postgres_batch).and_wrap_original do |original, first|
      started.enqueue(true)
      original.call(first)
    end
    allow(batched).to receive(:deliver_postgres_batch).and_wrap_original do |original, requests|
      original.call(requests)
      completed.enqueue(true)
    end
  end

  def change(id)
    { 'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages', 'id' => id,
      'timestamp' => '2026-09-02T12:00:00Z' }
  end

  def publish(data)
    socket.publication(channel: 'project:postgres:public:messages:user', data: data)
  end

  def wait_for(queue) = Async::Task.current.with_timeout(1) { queue.dequeue }
end
