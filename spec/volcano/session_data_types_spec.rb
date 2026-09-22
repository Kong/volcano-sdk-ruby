# frozen_string_literal: true

RSpec.describe Volcano::Session do
  it 'checks and runs a consumer of every generated record method' do
    fixture = File.expand_path('../../tests/types/data_records.rb', __dir__)
    source = File.read(fixture)
    output, errors, status = SteepConsumer.check(source)

    expect(status.success?).to be(true), output + errors
    expect { load(fixture) }.not_to raise_error
  end

  {
    'session.rb' => ['Ruby::UnresolvedOverloading', 'Ruby::ArgumentTypeMismatch'],
    'sign_up_result.rb' => ['Ruby::ArgumentTypeMismatch']
  }.each do |fixture, diagnostics|
    it "rejects invalid #{fixture} consumer values" do
      source = File.read(File.expand_path("../../tests/types_invalid/#{fixture}", __dir__))
      output, errors, status = SteepConsumer.check(source)

      expect(status.exitstatus).to eq(1), output + errors
      diagnostics.each { |diagnostic| expect(output).to include(diagnostic) }
    end
  end

  it 'ships both record signatures in the gem manifest' do
    files = Gem::Specification.load(File.expand_path('../../volcano-sdk.gemspec', __dir__)).files

    expect(files).to include('sig/session.rbs', 'sig/sign_up_result.rbs')
  end
end
