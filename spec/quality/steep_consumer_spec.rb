# frozen_string_literal: true

require 'open3'
require 'steep'
require 'tempfile'

RSpec.describe Steep do
  it 'rejects an invalid argument and undeclared method with Steep' do
    root = File.expand_path('../..', __dir__)
    Tempfile.create(['Steepfile-invalid-', ''], root) do |config|
      config.write(<<~STEEP)
        target :invalid_consumer do
          signature 'sig'
          check 'tests/invalid_types'
          configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
        end
      STEEP
      config.flush

      output, error, status = Open3.capture3(
        Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', "--steepfile=#{config.path}", '--jobs=1',
        'tests/invalid_types/public_consumer.rb', chdir: root
      )
      expect(status.exitstatus).to eq(1), error
      expect(output.scan(/Diagnostic ID: Ruby::\w+/)).to contain_exactly(
        'Diagnostic ID: Ruby::ArgumentTypeMismatch', 'Diagnostic ID: Ruby::NoMethod'
      )
    end
  end
end
