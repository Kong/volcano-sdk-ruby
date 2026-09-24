# frozen_string_literal: true

require 'open3'
require 'json'
require 'tmpdir'
require_relative '../support/coverage_policy'

RSpec.describe CoveragePolicy do
  let(:root) { File.expand_path('../..', __dir__) }

  def run_id_probe
    <<~RUBY
      require 'json'
      require 'rake'

      environments = []
      define_singleton_method(:sh) { |environment, *_arguments| environments << environment }
      load 'Rakefile'
      task = Rake::Task['quality:spec']
      2.times do
        task.reenable
        task.invoke
      end
      puts JSON.generate(environments)
    RUBY
  end

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

  it 'rejects disabled merge finalization' do
    contents = File.read(File.join(root, '.simplecov')).sub('merging true', "merging true\n  finalize_merge false")
    expect(check_config(contents)).to be(false)
  end

  it 'generates a fresh coverage run ID for each quality suite invocation' do
    output, error, status = Open3.capture3(Gem.ruby, '-e', run_id_probe, chdir: root)
    expect(status).to be_success, error

    runs = JSON.parse(output)
    ids = runs.map { |environment| environment.fetch('SIMPLECOV_RUN_ID') }
    expect(runs.length).to eq(2)
    expect(ids).to all(match(described_class::UUID))
    expect(ids.uniq.length).to eq(2)
    expect(runs.map { |environment| environment.fetch('VOLCANO_REQUIRE_FULL_SUITE') }).to all(eq('1'))
  end
end
