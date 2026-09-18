# frozen_string_literal: true

require 'spec_helper'
require_relative '../../features/support/presence_membership'
require_relative '../../features/support/contract_world'

RSpec.describe VolcanoContract::PresenceMembership do
  it 'cleans up using the native channel API' do
    clients = Array.new(2) { Volcano::Client.new(anon_key: 'anon', api_url: 'https://api.test') }
    world = instance_double(VolcanoContract::World, realtime_clients: clients,
                                                    realtime_channel: 'x' * 64, fixture: { 'user_id' => 'user' })
    clients.each do |client|
      allow(client.realtime).to receive(:channel).and_call_original
    end
    verifier = described_class.new(world)
    clients.each do |client|
      expect(client.realtime).to have_received(:channel).with('x' * 64, type: :presence)
    end
    allow(verifier).to receive(:check_membership).and_return([1, 2, 1])

    expect(Async { |task| verifier.run(task) }.wait).to eq([1, 2, 1])
  ensure
    Async { clients&.each { |client| client.realtime.disconnect } }.wait
  end

  [
    [[['first'], %w[first second], ['first']], true],
    [[['first'], %w[first second]], false],
    [[%w[first second], ['first']], false]
  ].each do |snapshots, expected|
    it "requires the original callback membership sequence: #{snapshots.inspect}" do
      verifier = described_class.allocate
      sequence = [['first'], %w[first second], ['first']]
      expect(verifier.send(:observed_membership?, snapshots, sequence)).to be(expected)
    end
  end
end
