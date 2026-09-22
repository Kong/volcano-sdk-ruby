# frozen_string_literal: true

RSpec.describe Volcano::StorageObject do
  it 'checks and runs the public storage record consumer' do
    fixture = File.expand_path('../../tests/types/storage_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid storage record consumers' do
    fixture = File.expand_path('../../tests/types_invalid/storage_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::UnresolvedOverloading')
  end

  it 'ships storage record signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/storage_records.rbs')
  end
end
