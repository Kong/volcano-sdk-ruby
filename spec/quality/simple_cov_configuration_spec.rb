# frozen_string_literal: true

require 'json'
require 'open3'
require 'simplecov'
require 'tmpdir'

RSpec.describe SimpleCov do
  let(:configuration) { File.read(File.expand_path('../../.simplecov', __dir__)) }

  def settings(source)
    Dir.mktmpdir('volcano-coverage-config-') do |directory|
      File.write(File.join(directory, '.simplecov'), source)
      output, error, status = Open3.capture3(Gem.ruby, '-r', 'simplecov', '-r', 'json', '-e', probe, chdir: directory)
      expect(status.exitstatus).to eq(0), error
      JSON.parse(output)
    end
  end

  def probe
    <<~RUBY
      filters = SimpleCov.filters.map do |filter|
        argument = filter.filter_argument
        [filter.class.name, argument.respond_to?(:source_location) ? File.basename(argument.source_location.first) : argument.to_s]
      end
      puts JSON.generate(
        criteria: SimpleCov.coverage_criteria.to_a.sort,
        minimum: SimpleCov.minimum_coverage,
        maximum_missed: SimpleCov.maximum_missed,
        cover_globs: SimpleCov.cover_globs,
        filters: filters,
        nocov_token: SimpleCov.current_nocov_token,
        ignored_branches: SimpleCov.ignored_branches
      )
    RUBY
  end

  def expect_strict_coverage(source)
    resolved = settings(source)
    expect(resolved).to include(
      'criteria' => %w[branch line], 'minimum' => { 'branch' => 100, 'line' => 100 },
      'maximum_missed' => { 'branch' => 0, 'line' => 0 }, 'cover_globs' => ['lib/**/*.rb'],
      'nocov_token' => 'nocov', 'ignored_branches' => []
    )
    expect(resolved.fetch('filters')).to eq(
      [['SimpleCov::StringFilter', '/vendor/bundle/'], ['SimpleCov::RegexFilter', '(?-mix:\\A\\..*)'],
       ['SimpleCov::BlockFilter', 'root_filter.rb'],
       ['SimpleCov::RegexFilter', '(?-mix:\\A(test|features|spec|autotest)\\/)'],
       ['SimpleCov::StringFilter', '/lib/volcano/generated/']]
    )
  end

  it 'keeps complete runtime inclusion and exact line and branch thresholds' do
    expect_strict_coverage(configuration)
  end

  it 'rejects a lowered coverage threshold' do
    weakened = configuration.sub('coverage :line, minimum: 100', 'coverage :line, minimum: 99')
    expect { expect_strict_coverage(weakened) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it 'rejects a broad runtime exclusion' do
    weakened = configuration.sub("skip '/lib/volcano/generated/'", "skip '/lib/volcano/'")
    expect { expect_strict_coverage(weakened) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it 'rejects a changed coverage-ignore token' do
    weakened = configuration.sub('merging true', "nocov_token 'skipcov'\n  merging true")
    expect { expect_strict_coverage(weakened) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end
end
