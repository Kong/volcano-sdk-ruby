# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rubygems/package'
require 'tmpdir'

RSpec.describe Gem::Package do
  let(:root) { File.expand_path('../..', __dir__) }

  def build_artifact(directory)
    artifact = File.join(directory, 'volcano-sdk.gem')
    output, error, status = Open3.capture3(
      Gem.ruby, '-S', 'gem', 'build', 'volcano-sdk.gemspec', '--output', artifact, chdir: root
    )
    expect(status).to be_success, "#{output}\n#{error}"
    artifact
  end

  def check_consumer(directory, source)
    File.write(File.join(directory, 'Steepfile'), <<~STEEP)
      target :consumer do
        signature 'sdk/sig'
        check '#{source}'
        library 'stringio'
        library 'tempfile'
        configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
      end
    STEEP
    Open3.capture3(Gem.ruby, Gem.bin_path('steep', 'steep'), 'check', '--jobs', '1', chdir: directory)
  end

  def with_packed_consumer
    Dir.mktmpdir('volcano-packed-types-') do |directory|
      artifact = build_artifact(directory)
      described_class.new(artifact).extract_files(File.join(directory, 'sdk'))
      FileUtils.cp_r(File.join(root, 'tests/types'), File.join(directory, 'valid'))
      FileUtils.cp_r(File.join(root, 'tests/invalid_types'), File.join(directory, 'invalid'))
      yield directory
    end
  end

  it 'packs every public signature without development signatures' do
    with_packed_consumer do |directory|
      signatures = Dir.glob(File.join(root, 'sig/**/*.rbs')).map { |path| path.delete_prefix("#{root}/") }
      packed = Dir.glob(File.join(directory, 'sdk/sig/**/*.rbs'))
                  .map { |path| path.delete_prefix("#{directory}/sdk/") }
      expect(signatures).not_to be_empty
      expect(packed).to eq(signatures)
      expect(Dir.glob(File.join(directory, 'sdk/sig_dev/**/*.rbs'))).to be_empty
    end
  end

  it 'types valid consumers and rejects invalid ones using only packed signatures' do
    with_packed_consumer do |directory|
      valid_output, valid_error, valid_status = check_consumer(directory, 'valid')
      expect(valid_status).to be_success, "#{valid_output}\n#{valid_error}"

      invalid_output, invalid_error, invalid_status = check_consumer(directory, 'invalid')
      expect(invalid_status.exitstatus).to eq(1), invalid_error
      expect(invalid_output.scan(/Diagnostic ID: Ruby::\w+/)).to contain_exactly(
        'Diagnostic ID: Ruby::ArgumentTypeMismatch', 'Diagnostic ID: Ruby::NoMethod'
      )
    end
  end
end
