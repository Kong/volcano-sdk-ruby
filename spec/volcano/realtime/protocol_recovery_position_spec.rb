# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'spec_helper'

ProtocolRecoveryPosition = Volcano::Realtime.const_get(:ProtocolRecoveryPosition, false)
RecoveryPositionProtocol = Volcano::Realtime.const_get(:Protocol, false)

class RecoveryPositionSocket
  def initialize
    @incoming = Async::Queue.new
  end

  def read = @incoming.dequeue

  def close = @incoming.enqueue(nil)
end

RSpec.describe ProtocolRecoveryPosition do
  around do |example|
    Async { example.run }.wait
  end

  let(:protocol) { RecoveryPositionProtocol.new(socket: RecoveryPositionSocket.new, task: Async::Task.current) }

  after { protocol.close }

  it 'advances only to the next same-epoch completion' do
    expect(position_after(current: ['epoch', 5], complete: ['epoch', 6])).to eq(epoch: 'epoch', offset: 6)
    expect(position_after(current: ['epoch', 5], complete: ['epoch', 5])).to eq(epoch: 'epoch', offset: 5)
    expect(
      position_after(current: ['epoch', 5], complete: ['epoch', 7], then_complete: ['epoch', 6])
    ).to eq(epoch: 'epoch', offset: 5)
  end

  it 'derives a publication epoch from the stored position' do
    protocol_set_position('epoch', 5)
    protocol.__send__(:complete_publication, 'channel', { 'offset' => 6 })

    expect(position).to eq(epoch: 'epoch', offset: 6)
  end

  it 'ignores dropped offsets at or behind the committed cursor' do
    expect(
      position_after(current: ['epoch', 5], drop: ['epoch', 3], then_complete: ['epoch', 6])
    ).to eq(epoch: 'epoch', offset: 6)
  end

  it 'does not advance at a recorded gap' do
    expect(
      position_after(current: ['epoch', 5], drop: ['epoch', 6], then_complete: ['epoch', 6])
    ).to eq(epoch: 'epoch', offset: 5)
  end

  it 'retains the earliest same-epoch gap' do
    protocol_set_position('epoch', 5)
    drop_publication('epoch', 8)
    drop_publication('epoch', 7)
    complete_publication('epoch', 6)
    complete_publication('epoch', 7)

    expect(position).to eq(epoch: 'epoch', offset: 6)
  end

  it 'does not advance after an epoch-mismatched drop' do
    protocol_set_position('epoch', 5)
    drop_publication('other-epoch', 6)
    complete_publication('epoch', 6)

    expect(position).to eq(epoch: 'epoch', offset: 5)
  end

  it 'ignores malformed offsets' do
    protocol_set_position('epoch', 5)
    complete_publication('epoch', '6')
    drop_publication('epoch', -1)

    expect(position).to eq(epoch: 'epoch', offset: 5)
    expect(protocol.__send__(:set_recovery_position, 'channel', 'epoch', '6')).to be_nil
  end

  it 'returns immutable positions' do
    position = protocol_set_position('epoch', 5)

    expect(position).to be_frozen
    expect(position.fetch(:epoch)).to be_frozen
    expect { position[:epoch] << 'changed' }.to raise_error(FrozenError)
  end

  it 'deletes both the stored position and its gap' do
    protocol_set_position('epoch', 5)
    drop_publication('epoch', 6)
    protocol.__send__(:delete_recovery_state, 'channel')

    expect(position).to be_nil

    protocol_set_position('epoch', 5)
    complete_publication('epoch', 6)

    expect(position).to eq(epoch: 'epoch', offset: 6)
  end

  private

  def position_after(current:, complete: nil, drop: nil, then_complete: nil)
    protocol_set_position(*current)
    drop_publication(*drop) if drop
    complete_publication(*complete) if complete
    complete_publication(*then_complete) if then_complete
    position
  end

  def protocol_set_position(epoch, offset)
    protocol.__send__(:set_recovery_position, 'channel', epoch, offset)
  end

  def complete_publication(epoch, offset)
    protocol.__send__(:complete_publication, 'channel', publication(epoch, offset))
  end

  def drop_publication(epoch, offset)
    protocol.__send__(:drop_publication, 'channel', publication(epoch, offset))
  end

  def position = protocol.__send__(:position, 'channel')

  def publication(epoch, offset) = { 'epoch' => epoch, 'offset' => offset }
end
