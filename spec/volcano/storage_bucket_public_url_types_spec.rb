# frozen_string_literal: true

RSpec.describe Volcano::StorageBucket do
  it 'checks and runs the public URL consumer' do
    fixture = File.expand_path('../../tests/types/storage_public_url.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid public URL consumers' do
    fixture = File.expand_path('../../tests/types_invalid/storage_public_url.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::InsufficientKeywordArguments')
    expect(output).to include('Ruby::ArgumentTypeMismatch')
  end

  it 'ships the public URL signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/storage_public_url.rbs')
  end
end
