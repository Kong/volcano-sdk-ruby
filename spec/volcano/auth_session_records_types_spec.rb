# frozen_string_literal: true

RSpec.describe Volcano::AuthSession do
  it 'checks and runs the public session record consumer' do
    fixture = File.expand_path('../../tests/types/auth_session_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  it 'rejects invalid session record consumers' do
    fixture = File.expand_path('../../tests/types_invalid/auth_session_records.rb', __dir__)
    output, errors, status = SteepConsumer.check(File.read(fixture))

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Ruby::ArgumentTypeMismatch')
    expect(output).to include('Ruby::UnresolvedOverloading')
  end

  it 'ships the session record signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/auth_session_records.rbs')
  end
end
