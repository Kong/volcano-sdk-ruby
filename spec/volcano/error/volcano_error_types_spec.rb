# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe Volcano::Error::VolcanoError do
  def check_consumer(source)
    Dir.mktmpdir('volcano-type-consumer-') do |directory|
      FileUtils.cp_r(File.expand_path('../../../sig', __dir__), File.join(directory, 'sig'))
      File.write(File.join(directory, 'consumer.rb'), source)
      File.write(File.join(directory, 'Steepfile'), <<~RUBY)
        target :consumer do
          signature 'sig'
          check 'consumer.rb'
          configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
        end
      RUBY
      Open3.capture3(
        Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', '--jobs', '1', chdir: directory
      )
    end
  end

  it 'accepts a typed consumer of the shipped errors' do
    source = File.read(File.expand_path('../../../tests/types/errors.rb', __dir__))
    output, errors, status = check_consumer(source)

    expect(status.success?).to be(true), output + errors
  end

  {
    "Volcano::Error::VolcanoError.new('error', status: '400')" => 'Ruby::ArgumentTypeMismatch',
    "Volcano::Error::VolcanoError.new('error').invented_method" => 'Ruby::NoMethod',
    "Volcano::Error::VolcanoError.new('error').retry_after.positive?" => 'Ruby::NoMethod'
  }.each do |source, diagnostic|
    it "rejects #{source}" do
      output, errors, status = check_consumer(source)

      expect(status.exitstatus).to eq(1), output + errors
      expect(output).to include(diagnostic)
    end
  end
end
