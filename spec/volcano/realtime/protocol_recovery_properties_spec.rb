# frozen_string_literal: true

require 'async'
require 'spec_helper'
require 'support/protocol_socket'

ProtocolRecoveryProperties = Volcano::Realtime.const_get(:ProtocolRecovery, false)

RSpec.describe ProtocolRecoveryProperties do
  let(:protocol) do
    Volcano::Realtime.const_get(:Protocol, false).new(
      socket: SpecSupport::ProtocolSocket.new, task: Async::Task.current
    )
  end
  let(:generators) { PropCheck::Generators }

  around { |example| Async { example.run }.wait }
  after { protocol.close }

  it 'delivers a contiguous retained batch before advancing the requested cursor' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(1..20))
    check_property(cases) { |base, count| assert_retained_batch(base, count) }
  end

  it 'starts initial recovery at the predecessor of the first retained publication' do
    cases = generators.tuple(generators.choose(1..100), generators.choose(1..20))
    check_property(cases) { |first, count| assert_initial_batch(first, count) }
  end

  it 'blocks cursor progress across a gap in retained publications' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(2..20))
    check_property(cases) { |base, gap| assert_retained_gap(base, gap) }
  end

  it 'retains the requested cursor when a response or publication is malformed' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(0..8))
    check_property(cases) { |base, kind| assert_malformed_recovery(base, kind) }
  end

  it 'does not accept a failed empty recovery as a new cursor' do
    cases = generators.tuple(generators.choose(0..100), generators.choose(1..20))
    check_property(cases) { |base, jump| assert_unrecovered_empty(base, jump) }
  end

  private

  def assert_retained_batch(base, count)
    publications = publications_from(base + 1, count)
    assert_recovered({ epoch: 'epoch', offset: base }, reply(base + count, publications), publications, base)
    assert_committed(publications, base + count)
  end

  def assert_initial_batch(first, count)
    publications = publications_from(first, count)
    assert_recovered({}, reply(first + count - 1, publications), publications, first - 1)
    assert_committed(publications, first + count - 1)
  end

  def assert_recovered(requested, result, publications, initial_offset)
    expect(recover(requested, result)).to eq(publications)
    expect(position).to eq(epoch: 'epoch', offset: initial_offset)
  end

  def assert_committed(publications, final_offset)
    publications.each { |publication| complete(publication) }
    expect(position).to eq(epoch: 'epoch', offset: final_offset)
  end

  def assert_retained_gap(base, gap)
    publication = { 'epoch' => 'epoch', 'offset' => base + gap }
    expect(recover({ epoch: 'epoch', offset: base }, reply(base + gap, [publication]))).to eq([publication])
    complete(publication)
    complete('epoch' => 'epoch', 'offset' => base + 1)
    expect(position).to eq(epoch: 'epoch', offset: base)
  end

  def assert_malformed_recovery(base, kind)
    requested = { epoch: 'epoch', offset: base }
    expect(recover(requested, malformed_reply(base, kind))).to eq([])
    complete('epoch' => 'epoch', 'offset' => base + 1)
    expect(position).to eq(requested)
  end

  def assert_unrecovered_empty(base, jump)
    result = reply(base + jump, []).merge('recovered' => false)
    expect(recover({ epoch: 'epoch', offset: base }, result)).to eq([])
    complete('epoch' => 'epoch', 'offset' => base + 1)
    expect(position).to eq(epoch: 'epoch', offset: base)
  end

  def malformed_reply(base, kind)
    return nil if kind.zero?
    return [] if kind == 1
    return reply(base + 1, {}) if kind == 2
    return reply(base + 1, [nil]) if kind == 3

    malformed_position(base, kind)
  end

  def malformed_position(base, kind)
    return malformed_result_position(base, kind) if kind <= 6

    malformed_publication_position(base, kind)
  end

  def malformed_result_position(base, kind)
    case kind
    when 4 then { 'epoch' => nil, 'offset' => base + 1 }
    when 5 then { 'epoch' => '', 'offset' => base + 1 }
    when 6 then { 'epoch' => 'epoch', 'offset' => '1' }
    end
  end

  def malformed_publication_position(base, kind)
    case kind
    when 7 then reply(base + 1, [{ 'epoch' => nil, 'offset' => base + 1 }])
    when 8 then reply(base + 1, [{ 'epoch' => 'epoch', 'offset' => -1 }])
    end
  end

  def publications_from(first, count)
    Array.new(count) { |index| { 'epoch' => 'epoch', 'offset' => first + index } }
  end

  def reply(offset, publications) = { 'epoch' => 'epoch', 'offset' => offset, 'publications' => publications }

  def recover(requested, result)
    protocol.__send__(:parse_recovery_result, channel: 'room', recovery: requested, result: result)
  end

  def complete(publication) = protocol.__send__(:complete_publication, 'room', publication)

  def position = protocol.__send__(:position, 'room')
end
