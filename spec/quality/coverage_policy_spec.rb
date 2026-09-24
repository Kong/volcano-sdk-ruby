# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require_relative '../support/coverage_policy'

RSpec.describe CoveragePolicy do
  let(:root) { File.expand_path('../..', __dir__) }

  def check_config(contents)
    Dir.mktmpdir('volcano-coverage-policy-') do |directory|
      File.write(File.join(directory, '.simplecov'), contents)
      _, error, status = Open3.capture3(
        Gem.ruby, '-r', File.join(root, 'spec/support/coverage_policy'),
        '-e', 'exit(CoveragePolicy.valid?(Dir.pwd) ? 0 : 3)', chdir: directory
      )
      raise error unless [0, 3].include?(status.exitstatus)

      return status.success?
    end
  end

  it 'keeps the effective SimpleCov configuration strict in the test process' do
    expect(described_class.valid?(root)).to be(true)
    expect(SimpleCov.started_in_this_process?).to be(true) if ENV['VOLCANO_REQUIRE_FULL_SUITE'] == '1'
  end

  it 'rejects a lowered line threshold' do
    contents = File.read(File.join(root, '.simplecov')).sub('coverage :line, minimum: 100',
                                                            'coverage :line, minimum: 99')
    expect(check_config(contents)).to be(false)
  end

  it 'rejects a new runtime exclusion' do
    replacement = "skip '/lib/volcano/generated/'\n  skip '/lib/volcano/auth.rb'"
    contents = File.read(File.join(root, '.simplecov')).sub("skip '/lib/volcano/generated/'", replacement)
    expect(check_config(contents)).to be(false)
  end

  it 'rejects a custom no-coverage token' do
    contents = File.read(File.join(root, '.simplecov')).sub('SimpleCov.configure do',
                                                            "SimpleCov.configure do\n  nocov_token 'hidden'")
    expect(check_config(contents)).to be(false)
  end

  it 'rejects a shared result directory' do
    contents = File.read(File.join(root, '.simplecov')).sub("coverage_dir \"reports/coverage/\#{SimpleCov.run_id}\"",
                                                            "coverage_dir 'reports/coverage'")
    expect(check_config(contents)).to be(false)
  end
end
