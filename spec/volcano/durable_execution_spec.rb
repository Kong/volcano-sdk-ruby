# frozen_string_literal: true

RSpec.describe Volcano::DurableExecution do
  let(:attributes) do
    { id: 'execution', function_id: 'function', name: 'job', status: 'running',
      region: 'aws-us-east-1', created_at: Time.utc(2026) }
  end

  it 'rejects unknown constructor fields' do
    expect { described_class.new(**attributes, unexpected: true) }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'rejects omitted required constructor fields' do
    expect { described_class.new(**attributes.except(:id)) }
      .to raise_error(ArgumentError, 'missing keywords: id')
  end
end
