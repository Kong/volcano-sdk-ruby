# frozen_string_literal: true

RSpec.describe Volcano::LockLease do
  it 'checks and runs consumers of both public lock records' do
    fixture = File.expand_path('../../tests/types/lock_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid lock record consumers' do
    fixture = File.expand_path('../../tests/types_invalid/lock_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::InsufficientPositionalArguments')
  end

  it 'ships the lock signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/lock_records.rbs')
  end
end
