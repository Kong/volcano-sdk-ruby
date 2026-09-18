# frozen_string_literal: true

require 'spec_helper'
require_relative '../../features/support/contract_world'
require_relative '../../features/support/logs_contract'

RSpec.describe VolcanoContract::Logs do
  let(:fixture) do
    { 'api_url' => 'https://api.test', 'anon_key' => 'anon',
      'logs_access_token' => 'project-token', 'function_id' => 'function-id' }
  end
  let(:world) { instance_double(VolcanoContract::World, fixture: fixture) }
  let(:contract) { described_class.new(world) }
  let(:events) do
    marker = contract.instance_variable_get(:@marker)
    Array.new(3) do |ordinal|
      { 'id' => "event-#{ordinal}", 'timestamp' => "2026-09-18T12:00:0#{2 - ordinal}Z",
        'body' => { 'marker' => marker, 'ordinal' => ordinal },
        'resource' => { 'type' => 'function', 'id' => 'function-id' }, 'level' => 'info' }
    end
  end
  let(:activity) do
    Volcano::LogActivityResponse.new(total: 1, data: [
                                       { 'total' => 1,
                                         'counts' => { 'resource_ids' => { 'function-id' => 1 },
                                                       'levels' => { 'info' => 1 } } },
                                       { 'total' => 0, 'counts' => { 'resource_ids' => {}, 'levels' => {} } }
                                     ])
  end

  it 'accepts structured events and rejects duplicate IDs' do
    contract.verify_events(events)
    expect { contract.verify_events([events[0], events[0], events[2]]) }
      .to raise_error(RuntimeError, 'missing or duplicate event IDs')
  end

  it 'rejects an event from another resource' do
    events[1]['resource']['id'] = 'another-function'
    expect { contract.verify_events(events) }.to raise_error(RuntimeError, 'event resource changed')
  end

  it 'accepts exact activity counts' do
    expect { contract.verify_activity(activity) }.not_to raise_error
  end

  it 'rejects counts from another resource' do
    data = Marshal.load(Marshal.dump(activity.data))
    data[0]['counts']['resource_ids'] = { 'another-function' => 1 }
    response = Volcano::LogActivityResponse.new(total: 1, data: data)
    expect { contract.verify_activity(response) }.to raise_error(RuntimeError, 'resource counts changed')
  end
end
