# frozen_string_literal: true

require 'async'
require 'spec_helper'
require 'support/protocol_socket'

ProtocolRecoveryPositionProperties = Volcano::Realtime.const_get(:ProtocolRecoveryPosition, false)

RSpec.describe ProtocolRecoveryPositionProperties do
  let(:protocol) do
    Volcano::Realtime.const_get(:Protocol, false).new(
      socket: SpecSupport::ProtocolSocket.new, task: Async::Task.current
    )
  end
  let(:generators) { PropCheck::Generators }

  around { |example| Async { example.run }.wait }
  after { protocol.close }

  it 'commits every contiguous completion without changing its epoch' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(0..25))
    check_property(cases) { |base, count| assert_contiguous(base, count) }
  end

  it 'never commits the earliest dropped offset in a retained stream' do
    bounded = generators.choose(1..25)
    cases = generators.tuple(generators.choose(0..100), bounded, bounded, bounded)
    check_property(cases) { |base, count, first, second| assert_dropped_gap(base, count, first, second) }
  end

  it 'does not fill an unknown gap after an out-of-order completion' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(2..25))
    check_property(cases) { |base, jump| assert_out_of_order(base, jump) }
  end

  it 'keeps independent channel positions separate through arbitrary actions' do
    action = generators.tuple(generators.choose(0..1), generators.choose(0..4), generators.choose(0..25))
    check_property(generators.array(action, min: 1, max: 30)) { |actions| assert_channel_isolation(actions) }
  end

  it 'ignores malformed publication metadata without poisoning the next completion' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(0..4))
    check_property(cases) { |base, kind| assert_malformed_publication(base, kind) }
  end

  it 'clears a recorded gap when recovery state is deleted' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(1..25))
    check_property(cases) { |base, gap| assert_reset(base, gap) }
  end

  private

  def assert_contiguous(base, count)
    reset('channel', 'epoch', base)
    (1..count).each { |delta| complete('channel', 'epoch', base + delta) }
    expect(position('channel')).to eq(epoch: 'epoch', offset: base + count)
  end

  def assert_dropped_gap(base, count, first, second)
    reset('channel', 'epoch', base)
    gaps = dropped_offsets(base, count, first, second)
    gaps.each { |offset| drop('channel', 'epoch', offset) }
    (1..count).each { |delta| complete('channel', 'epoch', base + delta) }
    expect(position('channel')).to eq(epoch: 'epoch', offset: gaps.min - 1)
  end

  def dropped_offsets(base, count, first, second)
    [first, second].map { |value| base + 1 + ((value - 1) % count) }
  end

  def assert_out_of_order(base, jump)
    reset('channel', 'epoch', base)
    complete('channel', 'epoch', base + jump)
    (1..jump).each { |delta| complete('channel', 'epoch', base + delta) }
    expect(position('channel')).to eq(epoch: 'epoch', offset: base)
  end

  def assert_channel_isolation(actions)
    %w[alpha beta].each { |channel| reset(channel, channel, 0) }
    actions.each do |index, action, offset|
      channel, other = index.zero? ? %w[alpha beta] : %w[beta alpha]
      unaffected = position(other)
      previous = position(channel)
      act(channel, action, offset)
      assert_cursor_transition(previous, position(channel), action, channel, offset)
      expect(position(other)).to eq(unaffected)
    end
  end

  def assert_cursor_transition(previous, current, action, channel, offset)
    return assert_completion_transition(previous, current) if action.zero?
    return expect(current).to eq(previous) if action <= 2
    return expect(current).to be_nil if action == 3

    expect(current).to eq(epoch: channel, offset: offset)
  end

  def assert_completion_transition(previous, current)
    return expect(current).to be_nil unless previous

    expect(current.fetch(:epoch)).to eq(previous.fetch(:epoch))
    expect(current.fetch(:offset)).to be_between(previous.fetch(:offset), previous.fetch(:offset) + 1)
  end

  def act(channel, action, offset)
    return publication_action(channel, action, offset) if action <= 2

    action == 3 ? protocol.__send__(:delete_recovery_state, channel) : reset(channel, channel, offset)
  end

  def publication_action(channel, action, offset)
    case action
    when 0 then complete(channel, channel, offset)
    when 1 then drop(channel, channel, offset)
    when 2 then drop(channel, 'other-epoch', offset)
    end
  end

  def assert_malformed_publication(base, kind)
    reset('channel', 'epoch', base)
    reject_invalid_publication(malformed_publication(kind))
    expect(position('channel')).to eq(epoch: 'epoch', offset: base)
    complete('channel', 'epoch', base + 1)
    expect(position('channel')).to eq(epoch: 'epoch', offset: base + 1)
  end

  def malformed_publication(kind)
    return nil if kind.zero?
    return false if kind == 1

    malformed_object(kind)
  end

  def malformed_object(kind)
    case kind
    when 2 then { 'epoch' => nil, 'offset' => 1 }
    when 3 then { 'epoch' => '', 'offset' => 1 }
    when 4 then { 'epoch' => 'epoch', 'offset' => '1' }
    end
  end

  def reject_invalid_publication(publication)
    protocol.__send__(:complete_publication, 'channel', publication)
    protocol.__send__(:drop_publication, 'channel', publication)
  end

  def assert_reset(base, gap)
    reset('channel', 'epoch', base)
    drop('channel', 'epoch', base + gap)
    reset('channel', 'epoch', base)
    complete('channel', 'epoch', base + 1)
    expect(position('channel')).to eq(epoch: 'epoch', offset: base + 1)
  end

  def reset(channel, epoch, offset)
    protocol.__send__(:delete_recovery_state, channel)
    protocol.__send__(:set_recovery_position, channel, epoch, offset)
  end

  def complete(channel, epoch, offset)
    protocol.__send__(:complete_publication, channel, publication(epoch, offset))
  end

  def drop(channel, epoch, offset)
    protocol.__send__(:drop_publication, channel, publication(epoch, offset))
  end

  def publication(epoch, offset) = { 'epoch' => epoch, 'offset' => offset }

  def position(channel) = protocol.__send__(:position, channel)
end
