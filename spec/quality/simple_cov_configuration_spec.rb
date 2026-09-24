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

  def strict_policy?(source)
    policy = resolved_policy(source)
    policy.fetch('criteria') == %w[branch line] &&
      policy.fetch('minimum') == { 'line' => 100, 'branch' => 100 } &&
      policy.fetch('maximum_missed') == { 'line' => 0, 'branch' => 0 } &&
      policy.fetch('cover_globs') == ['lib/**/*.rb'] &&
      policy.fetch('filters') == expected_filters
  end

  def expected_filters
    generated = ['value', '"/lib/volcano/generated/"']
    (resolved_policy("SimpleCov.configure {}\n").fetch('filters') + [generated]).sort_by(&:to_s)
  end

  it 'keeps native line and branch thresholds at 100% with only the generated-client exclusion' do
    expect(strict_policy?(configuration)).to be(true)
  end

  it 'rejects a lowered coverage threshold' do
    weakened = configuration.sub('coverage :line, minimum: 100', 'coverage :line, minimum: 99')
    expect(strict_policy?(weakened)).to be(false)
  end

  it 'rejects a broad runtime exclusion' do
    weakened = configuration.sub("skip '/lib/volcano/generated/'", "skip '/lib/volcano/'")
    expect(strict_policy?(weakened)).to be(false)
  end

  it 'rejects a block filter that hides runtime files' do
    weakened = configuration.sub(
      "skip '/lib/volcano/generated/'", "skip { |source| source.filename.include?('/lib/') }"
    )
    expect(strict_policy?(weakened)).to be(false)
  end
end
