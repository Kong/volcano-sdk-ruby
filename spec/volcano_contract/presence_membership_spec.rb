# frozen_string_literal: true

require_relative '../../features/support/presence_membership'

RSpec.describe VolcanoContract::PresenceMembership do
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
