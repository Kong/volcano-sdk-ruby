# frozen_string_literal: true

require 'open3'

# Compares Git's maintained Ruby files with RuboCop's own target discovery.
class RuboCopInventory
  def initialize(root)
    @root = root
  end

  def missing_sources
    sources = tracked.select { |path| path.end_with?('.rb') }
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
end
