# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'simplecov'
require 'tmpdir'

RSpec.describe SimpleCov do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:configuration) { File.read(File.join(root, '.simplecov')) }

  def resolved_policy(source)
    Dir.mktmpdir('volcano-coverage-policy-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'config'))
      path = File.join(directory, 'config/.simplecov')
      File.write(path, source)
      ruby = <<~RUBY
        load ARGV.fetch(0)
        filters = SimpleCov.filters.map(&:filter_argument).map do |value|
          value.is_a?(Proc) ? ['proc', value.source_location] : ['value', value.inspect]
        end
        puts JSON.generate(
          criteria: SimpleCov.coverage_criteria.to_a.sort,
          minimum: SimpleCov.minimum_coverage,
          maximum_missed: SimpleCov.maximum_missed,
          cover_globs: SimpleCov.cover_globs.uniq,
          nocov_token: SimpleCov.current_nocov_token,
          ignored_branches: SimpleCov.ignored_branches,
          filters: filters.uniq.sort_by(&:to_s)
        )
      RUBY
      output, errors, status = Open3.capture3(
        Gem.ruby, '-r', 'simplecov', '-r', 'json', '-e', ruby, path, chdir: directory
      )
      expect(status.exitstatus).to eq(0), errors
      JSON.parse(output)
    end
  end

  def expected_filters
    generated = ['value', '"/lib/volcano/generated/"']
    (resolved_policy("SimpleCov.configure {}\n").fetch('filters') + [generated]).sort_by(&:to_s)
  end

  it 'keeps native line and branch thresholds at 100% with only the generated-client exclusion' do
    policy = resolved_policy(configuration)
    guarded_settings = %w[criteria minimum maximum_missed cover_globs nocov_token ignored_branches]
    expect(policy.slice(*guarded_settings)).to eq(
      'criteria' => %w[branch line],
      'minimum' => { 'line' => 100, 'branch' => 100 },
      'maximum_missed' => { 'line' => 0, 'branch' => 0 },
      'cover_globs' => ['lib/**/*.rb'],
      'nocov_token' => 'nocov', 'ignored_branches' => []
    )
    expect(policy.fetch('filters')).to eq(expected_filters)
  end

  it 'rejects a lowered coverage threshold' do
    weakened = configuration.sub('coverage :line, minimum: 100', 'coverage :line, minimum: 99')
    expect(resolved_policy(weakened).fetch('minimum')).to include('line' => 99)
  end

  it 'rejects a renamed no-coverage token' do
    weakened = configuration.sub('  merging true', "  current_nocov_token 'skipcov'\n  merging true")
    expect(resolved_policy(weakened).fetch('nocov_token')).to eq('skipcov')
  end

  it 'rejects ignored branch categories' do
    weakened = configuration.sub('  merging true', "  ignore_branches :implicit_else\n  merging true")
    expect(resolved_policy(weakened).fetch('ignored_branches')).to eq(['implicit_else'])
  end

  it 'rejects a broad runtime exclusion' do
    weakened = configuration.sub("skip '/lib/volcano/generated/'", "skip '/lib/volcano/'")
    expect(resolved_policy(weakened).fetch('filters')).not_to eq(expected_filters)
  end

  it 'rejects a block filter that hides runtime files' do
    weakened = configuration.sub(
      "skip '/lib/volcano/generated/'", "skip { |source| source.filename.include?('/lib/') }"
    )
    expect(resolved_policy(weakened).fetch('filters')).not_to eq(expected_filters)
  end
end
