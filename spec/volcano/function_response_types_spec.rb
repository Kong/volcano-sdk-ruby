# frozen_string_literal: true

RSpec.describe Volcano::FunctionResponse do
  it 'checks and runs the public function response consumer' do
    fixture = File.expand_path('../../tests/types/function_response.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid function response consumers' do
    fixture = File.expand_path('../../tests/types_invalid/function_response.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::UnresolvedOverloading')
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::InsufficientPositionalArguments')
  end

  it 'ships the function response signature in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/function_response.rbs')
  end
end
