# frozen_string_literal: true

RSpec.describe Volcano::Transport do
  it 'rejects a JSON object with a non-string key' do
    expect { described_class.json_object({ status: 'ready' }) }.to raise_error(TypeError, 'Expected a JSON object')
  end

  it 'rejects database payloads without an array of rows' do
    expect { described_class.json_rows('data' => 'no rows') }.to raise_error(TypeError, 'Expected database rows')
  end

  it 'rejects non-finite JSON numbers' do
    expect { described_class.json_value(Float::INFINITY) }.to raise_error(TypeError, 'Expected a finite JSON number')
  end

  it 'rejects unsupported JSON values' do
    expect { described_class.json_value(Object.new) }.to raise_error(TypeError, 'Expected a JSON response')
  end

  it 'rejects cyclic and excessively nested response values' do
    cyclic_array = []
    cyclic_array << cyclic_array
    cyclic_hash = {}
    cyclic_hash['self'] = cyclic_hash
    deeply_nested = 101.times.reduce('value') { |value, _| [value] }

    [cyclic_array, cyclic_hash, deeply_nested].each do |value|
      expect { described_class.json_value(value) }.to raise_error(TypeError, 'Expected a JSON response')
    end
  end

  it 'rejects strings and object keys that cannot be encoded as JSON' do
    invalid = "\xFF".b

    expect { described_class.json_value('value' => invalid) }.to raise_error(TypeError, 'Expected a JSON response')
    expect { described_class.json_object({ invalid => 'value' }) }.to raise_error(TypeError, 'Expected a JSON response')
  end

  it 'allows repeated references to an acyclic response subtree' do
    subtree = { 'count' => 1 }
    copy = described_class.json_object({ 'left' => subtree, 'right' => subtree })

    expect(copy).to eq('left' => { 'count' => 1 }, 'right' => { 'count' => 1 })
    expect(copy.fetch('left')).not_to equal(subtree)
  end
end
