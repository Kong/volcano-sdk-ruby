# frozen_string_literal: true

require 'open3'
require 'steep'
require 'yaml'

RSpec.describe Steep::Project do
  let(:root) { File.expand_path('../..', __dir__) }

  def command(*arguments)
    output, error, status = Open3.capture3(*arguments, chdir: root)
    expect(status.success?).to be(true), error
    output
  end

  def maintained_files
    command('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z')
      .split("\0")
      .reject { |path| path.start_with?('lib/volcano/generated/', 'vendor/') }
  end

  it 'includes every handwritten runtime file in a Steep target' do
    sources = %w[Steepfile Steepfile.transport].flat_map do |steepfile|
      output = command(Gem.ruby, Gem.bin_path('steep', 'steep'), 'project', '--print', '--steepfile', steepfile)
      YAML.safe_load(output).fetch('targets').flat_map { |target| target.fetch('source_paths') }
    end
    runtime = maintained_files.grep(%r{\Alib/.*\.rb\z})

    expect(sources).to include(*runtime)
  end

  it 'includes every maintained Ruby file in RuboCop discovery' do
    linted = command(Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files').lines.map(&:strip)
    special_files = %w[Rakefile volcano-sdk.gemspec .simplecov]
    code = maintained_files.select do |path|
      path.end_with?('.rb') || special_files.include?(path)
    end

    expect(linted).to include(*code)
  end
end
