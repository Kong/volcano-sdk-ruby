# frozen_string_literal: true

require 'async'
require 'spec_helper'
require 'support/protocol_socket'

ProtocolRecoveryBoundaries = Volcano::Realtime.const_get(:ProtocolRecovery, false)

RSpec.describe ProtocolRecoveryBoundaries do
  let(:protocol_class) { Volcano::Realtime.const_get(:Protocol, false) }
  let(:protocol) { protocol_class.new(socket: SpecSupport::ProtocolSocket.new, task: Async::Task.current) }
  let(:requested) { { epoch: 'original', offset: 4 } }

  around { |example| Async { example.run }.wait }
  after { protocol.close }

  it 'keeps the requested cursor when retained publications change epoch' do
    publication = { 'epoch' => 'replacement', 'offset' => 5, 'data' => { 'value' => 'retained' } }
    result = { 'epoch' => 'replacement', 'offset' => 5, 'publications' => [publication] }

    expect(recover(result)).to eq([publication])
    protocol.__send__(:complete_publication, 'room', publication)
    protocol.__send__(:complete_publication, 'room', { 'epoch' => 'original', 'offset' => 5 })

    expect(protocol.__send__(:position, 'room')).to eq(requested)
  end

  [nil, 'publication', 5].each do |publication|
    it "blocks cursor advancement after a malformed retained publication: #{publication.inspect}" do
      result = { 'epoch' => 'original', 'offset' => 5, 'publications' => [publication] }

      expect(recover(result)).to eq([])
      protocol.__send__(:complete_publication, 'room', { 'epoch' => 'original', 'offset' => 5 })

      expect(protocol.__send__(:position, 'room')).to eq(requested)
    end
  end

  it 'refuses a retained zero offset without a valid predecessor cursor' do
    result = { 'epoch' => 'original', 'offset' => 0, 'publications' => [{ 'offset' => 0 }] }

    expect(protocol.__send__(:parse_recovery_result, channel: 'room', recovery: {}, result: result)).to eq([])
    expect(protocol.__send__(:position, 'room')).to be_nil
  end

  private

  def recover(result)
    protocol.__send__(:parse_recovery_result, channel: 'room', recovery: requested, result: result)
  end
end
