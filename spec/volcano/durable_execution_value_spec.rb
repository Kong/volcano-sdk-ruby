# frozen_string_literal: true

RSpec.describe Volcano::DurableExecution do
  def execution(result)
    described_class.new(
      id: 'execution', function_id: 'function', name: 'run', status: 'succeeded',
      region: 'aws-us-east-1', created_at: Time.utc(2026, 9, 24), result: result
    )
  end

  it 'owns immutable nested result values independently of callers' do
    check_property(PropCheck::Generators.printable_string) do |text|
      value = "original:#{text}"
      record = execution('nested' => [value])
      value.replace('changed')

      expect(record.result).to eq('nested' => ["original:#{text}"])
      expect(record.result.fetch('nested')).to be_frozen
      expect(record.result.fetch('nested').first).to be_frozen
    end
  end

  it 'rejects cyclic result values instead of recursing indefinitely' do
    result = {}
    result['self'] = result

    expect { execution(result) }.to raise_error(TypeError, 'Request value contains a cycle')
  end
end
