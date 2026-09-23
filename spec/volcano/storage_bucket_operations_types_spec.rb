# frozen_string_literal: true

RSpec.describe Volcano::StorageBucket do
  it 'accepts typed storage consumers' do
    fixture = File.expand_path('../../tests/types/storage_operations.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
  end

  it 'rejects unsafe storage consumers' do
    fixture = File.expand_path('../../tests/types_invalid/storage_operations.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output.scan('Ruby::ArgumentTypeMismatch').length).to eq(3)
  end

  it 'ships the storage signatures in the gem' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/storage.rbs')
  end
end
