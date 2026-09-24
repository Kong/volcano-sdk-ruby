# frozen_string_literal: true

require 'json'
require 'open3'
require 'rubocop'

# Verifies the file sets and result produced by the native quality tools.
module NativeGate
  ROOT_CONFIGS = %w[.rubocop .rubocop.yml].freeze
  GENERATED_CONFIG = 'lib/volcano/generated/.rubocop.yml'
  DEFAULT_RUBY = RuboCop::ConfigLoader.default_configuration.for_all_cops
  RUBY_GLOBS = DEFAULT_RUBY.fetch('Include').freeze
  RUBY_SHEBANG = /\A#!.*#{Regexp.union(DEFAULT_RUBY.fetch('RubyInterpreters'))}/

  def self.verify_lint_targets!(root)
    paths = tracked(root)
    verify_root_configs!(paths)
    missing = ruby_sources(root, paths) - rubocop_targets(root)
    raise "Ruby files absent from RuboCop: #{missing.join(', ')}" unless missing.empty?
  end

  def self.verify_coverage!(root, run_id)
    path = File.join(root, 'reports', 'coverage', run_id, 'coverage.json')
    raise "Missing SimpleCov report for this run: #{path}" unless File.file?(path)

    report = JSON.parse(File.read(path))
    verify_coverage_totals!(report)
    verify_runtime_files!(root, report)
  end

  def self.verify_runtime_files!(root, report)
    runtime = tracked(root).grep(%r{\Alib/.*\.rb\z})
    runtime.reject! { |source| source.start_with?('lib/volcano/generated/') }
    missing = runtime - report.fetch('coverage').keys
    raise "Runtime files absent from SimpleCov: #{missing.join(', ')}" unless missing.empty?
  end

  def self.verify_coverage_totals!(report)
    %w[lines branches].each do |criterion|
      total = report.fetch('total').fetch(criterion)
      next if total.fetch('total').positive? && total.fetch('missed').zero? &&
              total.fetch('covered') == total.fetch('total')

      raise "Incomplete #{criterion} coverage in SimpleCov report"
    end
  end

  def self.verify_root_configs!(paths)
    nested = paths.grep(%r{(?:\A|/)\.rubocop(?:\.yml)?\z}) - ROOT_CONFIGS - [GENERATED_CONFIG]
    raise "Nested RuboCop configuration: #{nested.join(', ')}" unless nested.empty?
  end

  def self.ruby_sources(root, paths)
    sources = paths.select { |path| ruby_source?(root, path) }
    sources.reject! { |path| path.start_with?('lib/volcano/generated/', 'vendor/') }
    sources
  end

  def self.rubocop_targets(root)
    output, error, status = Open3.capture3(Gem.ruby, Gem.bin_path('rubocop', 'rubocop'),
                                           '--list-target-files', chdir: root)
    raise error unless status.success?

    output.lines.map(&:strip)
  end

  def self.tracked(root)
    output, error, status = Open3.capture3('git', 'ls-files', '--cached', '--others', '--exclude-standard',
                                           '-z', chdir: root)
    raise error unless status.success?

    output.split("\0")
  end

  def self.ruby_source?(root, path)
    return true if RUBY_GLOBS.any? { |glob| File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
    return false unless File.extname(path).empty?

    File.open(File.join(root, path), &:readline).match?(RUBY_SHEBANG)
  rescue EOFError
    false
  end
  private_class_method :verify_coverage_totals!, :verify_runtime_files!, :verify_root_configs!, :ruby_sources,
                       :rubocop_targets, :tracked, :ruby_source?
end
