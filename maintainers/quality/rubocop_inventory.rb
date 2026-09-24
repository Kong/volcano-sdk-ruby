# frozen_string_literal: true

require 'open3'
require 'rubocop'

# Compares Git's maintained Ruby files with RuboCop's own target discovery.
class RuboCopInventory
  DEFAULT_RUBY = RuboCop::ConfigLoader.default_configuration.for_all_cops
  RUBY_GLOBS = DEFAULT_RUBY.fetch('Include').freeze
  RUBY_INTERPRETERS = Regexp.union(DEFAULT_RUBY.fetch('RubyInterpreters')).freeze
  RUBY_SHEBANG = /\A#!.*#{RUBY_INTERPRETERS}/

  def initialize(root)
    @root = root
  end

  def missing_sources
    sources = tracked.select { |path| ruby_source?(path) }
    sources.reject! { |path| path.start_with?('lib/volcano/generated/', 'vendor/') }
    (sources.to_set - targets).to_a.sort
  end

  def nested_configs
    tracked.grep(%r{(?:\A|/)\.rubocop(?:\.yml)?\z}) -
      ['.rubocop', '.rubocop.yml', 'lib/volcano/generated/.rubocop.yml']
  end

  private

  def tracked
    output, error, status = Open3.capture3('git', 'ls-files', '--cached', '--others', '--exclude-standard',
                                           '-z', chdir: @root)
    raise error unless status.success?

    output.split("\0")
  end

  def targets
    output, error, status = Open3.capture3(Gem.ruby, Gem.bin_path('rubocop', 'rubocop'),
                                           '--list-target-files', chdir: @root)
    raise error unless status.success?

    output.lines.to_set(&:strip)
  end

  def ruby_source?(path)
    return true if RUBY_GLOBS.any? { |glob| File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) }
    return false unless File.extname(path).empty?

    File.open(File.join(@root, path), &:readline).match?(RUBY_SHEBANG)
  rescue EOFError
    false
  end
end
