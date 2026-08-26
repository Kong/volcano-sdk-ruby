# frozen_string_literal: true

require_relative '../../lib/volcano'
require_relative 'contract_world'
require_relative 'fixture'

fixture_path = ENV.fetch('VOLCANO_SDK_CONTRACT_FIXTURE') do
  raise 'VOLCANO_SDK_CONTRACT_FIXTURE is required'
end
CONTRACT_FIXTURE = VolcanoContract.load_fixture(fixture_path)

Before do
  @contract = VolcanoContract::World.new(CONTRACT_FIXTURE)
end

After do
  @contract&.cleanup
end
