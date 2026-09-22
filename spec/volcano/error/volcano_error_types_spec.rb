# frozen_string_literal: true

RSpec.describe Volcano::Error::VolcanoError do
  it 'accepts a typed consumer of the shipped errors' do
    source = File.read(File.expand_path('../../../tests/types/errors.rb', __dir__))
    output, errors, status = SteepConsumer.check(source)

    expect(status.success?).to be(true), output + errors
  end

  {
    "Volcano::Error::VolcanoError.new('error', status: '400')" => 'Ruby::ArgumentTypeMismatch',
    "Volcano::Error::VolcanoError.new('error').invented_method" => 'Ruby::NoMethod',
    "Volcano::Error::VolcanoError.new('error').retry_after.positive?" => 'Ruby::NoMethod'
  }.each do |source, diagnostic|
    it "rejects #{source}" do
      output, errors, status = SteepConsumer.check(source)

      expect(status.exitstatus).to eq(1), output + errors
      expect(output).to include(diagnostic)
    end
  end
end
