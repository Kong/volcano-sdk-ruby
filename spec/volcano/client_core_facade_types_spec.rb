# frozen_string_literal: true

RSpec.describe Volcano::Client do
  it 'checks and runs a consumer of the core facades' do
    fixture = File.expand_path('../../tests/types/core_facades.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid core facade calls' do
    fixture = File.expand_path('../../tests/types_invalid/core_facades.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'ships the public core facade signatures' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/client.rbs', 'sig/core_facades.rbs', 'sig/locks.rbs')
  end
end
