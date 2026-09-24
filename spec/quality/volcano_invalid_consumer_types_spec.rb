# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe Volcano do
  let(:root) { File.expand_path('../..', __dir__) }

  it 'rejects invalid arguments and undeclared methods with Steep' do
    Dir.mktmpdir('volcano-invalid-consumer-') do |directory|
      File.symlink(File.join(root, 'sig'), File.join(directory, 'sig'))
      FileUtils.cp(File.join(root, 'tests/invalid_types/public_consumer.rb'), File.join(directory, 'consumer.rb'))
      File.write(File.join(directory, 'Steepfile'), <<~STEEP)
        target :consumer do
          signature 'sig'
          check 'consumer.rb'
          configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
        end
      STEEP

      output, errors, status = Open3.capture3(
        Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', '--jobs', '1',
        "--steepfile=#{File.join(directory, 'Steepfile')}", chdir: root
      )
      expect(status.exitstatus).to eq(1), errors
      expect(output.scan('Ruby::ArgumentTypeMismatch').length).to eq(2)
      expect(output).to include('Ruby::NoMethod')
    end
  end
end
