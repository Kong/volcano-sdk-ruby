# frozen_string_literal: true

RSpec.describe Volcano::LockGuard do
  it 'checks the public guard methods against the packed signatures' do
    fixture = File.expand_path('../../tests/types/lock_guard.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects a nonnumeric lock wait timeout' do
    fixture = File.expand_path('../../tests/types_invalid/lock_guard.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::InsufficientPositionalArguments')
  end

  it 'rejects a complex lock wait timeout' do
    fixture = File.expand_path('../../tests/types_invalid/lock_guard_complex.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'ships the public guard signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/lock_guard.rbs')
  end
end
