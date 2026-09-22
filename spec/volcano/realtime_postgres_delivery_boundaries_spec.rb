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
    client.realtime.database_name = 'app'
    batched = client.realtime.channel('public:messages', type: :postgres, fetch_batch_window_ms: 10_000)
    batched.on('*') { |change| delivered.enqueue(change) }
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

  private

  def change(id)
    { 'type' => 'UPDATE', 'schema' => 'public', 'table' => 'messages', 'id' => id,
      'timestamp' => '2026-09-02T12:00:00Z' }
  end

  def publish(data)
    socket.publication(channel: 'project:postgres:public:messages:user', data: data)
  end

  def wait_for(queue) = Async::Task.current.with_timeout(1) { queue.dequeue }
end
