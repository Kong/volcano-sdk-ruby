# frozen_string_literal: true

require 'open3'
require 'tmpdir'

class CoveragePolicy
  PROBE = <<~'RUBY'
    require 'simplecov'

    abort 'coverage thresholds changed' unless SimpleCov.minimum_coverage == { line: 100, branch: 100 }
    abort 'missed-line allowance changed' unless SimpleCov.maximum_missed == { line: 0, branch: 0 }
    abort 'coverage root changed' unless SimpleCov.root == Dir.pwd
    abort 'runtime file discovery changed' unless SimpleCov.cover_filters.map(&:filter_argument) == ['lib/**/*.rb']

    filters = SimpleCov.filters
    abort 'coverage exclusions changed' unless filters.length == 5
    abort 'coverage exclusions changed' unless filters[0].filter_argument == '/vendor/bundle/'
    abort 'coverage exclusions changed' unless filters[1].filter_argument == /\A\..*/
    abort 'coverage exclusions changed' unless filters[2].filter_argument.source_location.first
                                                      .start_with?(Gem.loaded_specs.fetch('simplecov').full_gem_path)
    abort 'coverage exclusions changed' unless filters[3].filter_argument == /\A(test|features|spec|autotest)\//
    abort 'coverage exclusions changed' unless filters[4].filter_argument == '/lib/volcano/generated/'
  RUBY

  def self.check(directory)
    Open3.capture3(Gem.ruby, '-e', PROBE, chdir: directory)
  end
end

RSpec.describe CoveragePolicy do
  let(:root) { File.expand_path('../..', __dir__) }

  it 'requires every handwritten runtime file to have full line and branch coverage' do
    output, error, status = described_class.check(root)

    expect(status).to be_success, output + error
  end

  it 'keeps thresholds active in the instrumented RSpec process' do
    expect(described_class.check(root).last).to be_success
    next unless ENV['VOLCANO_REQUIRE_FULL_SUITE'] == '1'

    expect(SimpleCov.started_in_this_process?).to be(true)
    expect(SimpleCov.minimum_coverage).to eq(line: 100, branch: 100)
    expect(SimpleCov.maximum_missed).to eq(line: 0, branch: 0)
  end

  it 'keeps runtime discovery active in the instrumented RSpec process' do
    expect(described_class.check(root).last).to be_success
    next unless ENV['VOLCANO_REQUIRE_FULL_SUITE'] == '1'

    expect(SimpleCov.root).to eq(root)
    expect(SimpleCov.cover_filters.map(&:filter_argument)).to eq(['lib/**/*.rb'])
    expect(SimpleCov.filters.map(&:filter_argument)).to eq(
      ['/vendor/bundle/', /\A\..*/, SimpleCov.filters[2].filter_argument,
       %r{\A(test|features|spec|autotest)/}, '/lib/volcano/generated/']
    )
    expect(SimpleCov.filters[2].filter_argument.source_location.first)
      .to start_with(Gem.loaded_specs.fetch('simplecov').full_gem_path)
  end

  it 'rejects a lowered coverage threshold' do
    Dir.mktmpdir('volcano-coverage-policy-') do |directory|
      original = File.read(File.join(root, '.simplecov'))
      File.write(
        File.join(directory, '.simplecov'), original.sub('coverage :line, minimum: 100',
                                                         'coverage :line, minimum: 99')
      )
      _, error, status = described_class.check(directory)

      expect(status).not_to be_success
      expect(error).to include('coverage thresholds changed')
    end
  end

  it 'rejects an exclusion of handwritten runtime files' do
    Dir.mktmpdir('volcano-coverage-policy-') do |directory|
      original = File.read(File.join(root, '.simplecov'))
      changed = original.sub("skip '/lib/volcano/generated/'", <<~RUBY.chomp)
        skip '/lib/volcano/generated/'
        skip '/lib/volcano/transport_json.rb'
      RUBY
      File.write(File.join(directory, '.simplecov'), changed)
      _, error, status = described_class.check(directory)

      expect(status).not_to be_success
      expect(error).to include('coverage exclusions changed')
    end
  end

  it 'rejects a changed SimpleCov root that would hide unloaded runtime files' do
    Dir.mktmpdir('volcano-coverage-policy-') do |directory|
      original = File.read(File.join(root, '.simplecov'))
      changed = original.sub('SimpleCov.configure do', "SimpleCov.configure do\n  root File.dirname(__dir__)")
      File.write(File.join(directory, '.simplecov'), changed)
      _, error, status = described_class.check(directory)

      expect(status).not_to be_success
      expect(error).to include('coverage root changed')
    end
  end
end
