# frozen_string_literal: true

RSpec.describe Volcano::EmailChangeResult do
  it 'checks and runs the public record consumer' do
    fixture = File.expand_path('../../tests/types/email_change_result.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid consumer calls' do
    fixture = File.expand_path('../../tests/types_invalid/email_change_result.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::InsufficientPositionalArguments')
  end

  it 'ships the record signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/email_change_result.rbs')
  end
end
