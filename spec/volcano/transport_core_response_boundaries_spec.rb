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
end
