# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'json'
require 'spec_helper'

ProtocolRecovery = Volcano::Realtime.const_get(:ProtocolRecovery, false)
RecoveryProtocol = Volcano::Realtime.const_get(:Protocol, false)

class RecoverySocket
  attr_accessor :on_write

  def initialize
    @incoming = Async::Queue.new
  end

  def write(message)
    on_write&.call(JSON.parse(message))
  end

  def read = @incoming.dequeue

  def receive(frame) = @incoming.enqueue(JSON.generate(frame))

  def close = @incoming.enqueue(nil)
end

RSpec.describe ProtocolRecovery do
  around do |example|
    Async { example.run }.wait
  end

  let(:socket) { RecoverySocket.new }
  let(:protocol) { RecoveryProtocol.new(socket: socket, task: Async::Task.current) }

  after { protocol.close }

  it 'keeps an ordinary subscribe command exact' do
    expect(RecoveryProtocol.subscribe(id: 7, channel: 'room')).to eq(
      'id' => 7,
      'subscribe' => { 'channel' => 'room' }
    )
  end

  it 'builds a positioned recovery subscribe command' do
    expect(
      RecoveryProtocol.subscribe(id: 7, channel: 'room', recovery: { epoch: 'e', offset: 4 })
    ).to eq(
      'id' => 7,
      'subscribe' => {
        'channel' => 'room', 'recover' => true, 'positioned' => true,
        'recoverable' => true, 'epoch' => 'e', 'offset' => 4
      }
    )
  end

  it 'builds an initial recoverable subscribe command from an empty recovery hash' do
    expect(RecoveryProtocol.subscribe(id: 7, channel: 'room', recovery: {})).to eq(
      'id' => 7,
      'subscribe' => {
        'channel' => 'room', 'recover' => true, 'positioned' => true, 'recoverable' => true
      }
    )
  end

  it 'preserves presence options in a recovery subscribe command' do
    expect(
      RecoveryProtocol.subscribe(
        id: 7,
        channel: 'room',
        recovery: { epoch: 'e', offset: 4 },
        join_leave: true
      )
    ).to eq(
      'id' => 7,
      'subscribe' => {
        'channel' => 'room', 'recover' => true, 'positioned' => true,
        'recoverable' => true, 'epoch' => 'e', 'offset' => 4, 'join_leave' => true
      }
    )
  end

  it 'installs a recovery baseline from a successful subscribe reply' do
    socket.on_write = lambda do |command|
      socket.receive(
        'id' => command.fetch('id'),
        'result' => { 'epoch' => 'e', 'offset' => 4, 'publications' => [] }
      )
    end

    expect(protocol.subscribe(channel: 'room', recovery: { epoch: 'e', offset: 3 })).to eq(
      'epoch' => 'e', 'offset' => 4, 'publications' => []
    )
    expect(position).to eq(epoch: 'e', offset: 4)
  end

  it 'uses the server position when an empty recovery result has a requested cursor' do
    retained = protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: { epoch: 'requested', offset: 3 },
      result: { 'epoch' => 'server', 'offset' => 9, 'publications' => [] }
    )

    expect(retained).to eq([])
    expect(position).to eq(epoch: 'server', offset: 9)
  end

  it 'installs a requested cursor before returning retained publications' do
    publications = [
      { 'epoch' => 'e', 'offset' => 4, 'data' => { 'event' => 'one' } },
      { 'epoch' => 'e', 'offset' => 5, 'data' => { 'event' => 'two' } }
    ]

    retained = protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: { epoch: 'e', offset: 3 },
      result: { 'epoch' => 'e', 'offset' => 5, 'publications' => publications }
    )

    expect(position).to eq(epoch: 'e', offset: 3)
    expect(retained).to eq(publications)
  end

  it 'records the successor of a requested cursor as a gap before a retained batch' do
    protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: { epoch: 'e', offset: 3 },
      result: {
        'epoch' => 'e',
        'offset' => 6,
        'publications' => [{ 'epoch' => 'e', 'offset' => 6, 'data' => { 'event' => 'after-gap' } }]
      }
    )

    protocol.__send__(:complete_publication, 'room', { 'epoch' => 'e', 'offset' => 4 })

    expect(position).to eq(epoch: 'e', offset: 3)
  end

  it 'initializes an initial recovery request before its first retained offset' do
    retained = protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: {},
      result: {
        'epoch' => 'e',
        'offset' => 5,
        'publications' => [{ 'epoch' => 'e', 'offset' => 4, 'data' => { 'event' => 'retained' } }]
      }
    )

    expect(position).to eq(epoch: 'e', offset: 3)
    expect(retained).to eq([{ 'epoch' => 'e', 'offset' => 4, 'data' => { 'event' => 'retained' } }])
  end

  it 'keeps the requested cursor when a recovery result is malformed' do
    protocol.__send__(:set_recovery_position, 'room', 'e', 3)

    protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: { epoch: 'e', offset: 3 },
      result: []
    )

    expect(position).to eq(epoch: 'e', offset: 3)
    protocol.__send__(:complete_publication, 'room', { 'epoch' => 'e', 'offset' => 4 })
    expect(position).to eq(epoch: 'e', offset: 3)
  end

  it 'keeps recovery state when publications are not an array' do
    protocol.__send__(:set_recovery_position, 'room', 'e', 3)

    protocol.__send__(
      :parse_recovery_result,
      channel: 'room',
      recovery: { epoch: 'e', offset: 3 },
      result: { 'epoch' => 'e', 'offset' => 4, 'publications' => {} }
    )

    expect(position).to eq(epoch: 'e', offset: 3)
    protocol.__send__(:complete_publication, 'room', { 'epoch' => 'e', 'offset' => 4 })
    expect(position).to eq(epoch: 'e', offset: 3)
  end

  it 'keeps recovery state when result or retained publication positions are malformed' do
    protocol.__send__(:set_recovery_position, 'room', 'e', 3)

    invalid_results = [
      { 'epoch' => '', 'offset' => 4, 'publications' => [] },
      { 'epoch' => 'e', 'offset' => -1, 'publications' => [] },
      { 'epoch' => 'e', 'offset' => 4, 'publications' => [{ 'epoch' => '', 'offset' => 4 }] },
      { 'epoch' => 'e', 'offset' => 4, 'publications' => [{ 'epoch' => 'e', 'offset' => '4' }] }
    ]

    invalid_results.each do |result|
      protocol.__send__(
        :parse_recovery_result,
        channel: 'room',
        recovery: { epoch: 'e', offset: 3 },
        result: result
      )
    end

    expect(position).to eq(epoch: 'e', offset: 3)
    protocol.__send__(:complete_publication, 'room', { 'epoch' => 'e', 'offset' => 4 })
    expect(position).to eq(epoch: 'e', offset: 3)
  end

  it 'does not install recovery state for failed recovery subscribe replies' do
    socket.on_write = lambda do |command|
      socket.receive(
        'id' => command.fetch('id'),
        'error' => { 'code' => 107, 'message' => 'bad request' }
      )
    end

    expect do
      protocol.subscribe(channel: 'room', recovery: { epoch: 'e', offset: 3 })
    end.to raise_error(Volcano::Realtime::ServerError, 'bad request') { |error| expect(error.code).to eq(107) }
    expect(position).to be_nil
  end

  private

  def position = protocol.__send__(:position, 'room')
end
