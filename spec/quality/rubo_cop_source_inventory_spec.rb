# frozen_string_literal: true

require 'open3'
require 'rubocop'
require 'tmpdir'

class RuboCopSourceInventory
  RUBY_ENTRYPOINTS = %w[.simplecov Gemfile Rakefile Steepfile volcano-sdk.gemspec bin/check-defects].freeze
  RUBY_SUFFIXES = %w[.rb .rake .gemspec .ru].freeze
  ROOT_CONFIGS = %w[.rubocop .rubocop.yml lib/volcano/generated/.rubocop.yml].freeze
  COP_SCOPE_KEYS = %w[Include Exclude AllowedMethods AllowedPatterns].freeze

  def initialize(root)
    @root = root
  end

  def files
    output, error, status = Open3.capture3(
      'git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', chdir: @root
    )
    raise error unless status.success?

    output.split("\0")
  end

  def unexpected_configs
    files.grep(%r{(?:\A|/)\.rubocop(?:_todo)?(?:\.yml)?\z}) - ROOT_CONFIGS
  end

  def inherited_configs
    configuration = RuboCop::ConfigLoader.load_yaml_configuration(File.join(@root, '.rubocop.yml'))
    configuration.keys & %w[inherit_from inherit_gem]
  end

  def new_cops_enabled?
    configuration = RuboCop::ConfigLoader.load_file(File.join(@root, '.rubocop.yml'))
    configuration.fetch('AllCops').fetch('NewCops') == 'enable'
  end

  def metrics_apply_everywhere?(config: File.join(@root, '.rubocop.yml'))
    configuration = RuboCop::ConfigLoader.load_file(config)
    %w[Metrics Metrics/CyclomaticComplexity Metrics/MethodLength].all? do |name|
      options = configuration.fetch(name, {})
      COP_SCOPE_KEYS.all? { |key| options.fetch(key, []).empty? }
    end
  end

  def maintained_ruby
    paths = files.select do |path|
      path.end_with?(*RUBY_SUFFIXES) || RUBY_ENTRYPOINTS.include?(path) || ruby_shebang?(path)
    end
    paths.reject! { |path| path.start_with?('lib/volcano/generated/') }
    paths
  end

  def ruby_shebang?(path)
    return false unless File.file?(File.join(@root, path))

    first_line = File.binread(File.join(@root, path), 256).split("\n", 2).first
    first_line.match?(/\A#!.*\bruby(?:\d+(?:\.\d+)*)?(?:\s|\z)/n)
  end

  def missing_lint_targets(config: nil)
    arguments = [Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files']
    arguments.push('--config', config) if config
    output, error, status = Open3.capture3(*arguments, chdir: @root)
    raise error unless status.success?

    maintained_ruby - output.lines.map { |line| line.strip.delete_prefix('./') }
  end
end

RSpec.describe RuboCopSourceInventory do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:inventory) { described_class.new(root) }

  it 'lints every maintained Ruby source and entrypoint through native discovery' do
    expect(inventory.missing_lint_targets).to be_empty
  end

  it 'rejects nested overrides, debt files, and inherited configuration' do
    expect(inventory.unexpected_configs).to be_empty
    expect(inventory.inherited_configs).to be_empty
    expect(inventory.new_cops_enabled?).to be(true)
    expect(inventory.metrics_apply_everywhere?).to be(true)
  end

  it 'detects a source file excluded from RuboCop discovery' do
    Dir.mktmpdir('volcano-rubocop-config-') do |directory|
      config = File.join(directory, '.rubocop.yml')
      File.write(config, <<~YAML)
        inherit_from: #{root}/.rubocop.yml
        AllCops:
          Exclude:
            - #{root}/lib/volcano/transport_json.rb
      YAML

      expect(inventory.missing_lint_targets(config:)).to include('lib/volcano/transport_json.rb')
    end
  end

  it 'detects cop-specific narrowing that would spare real source files' do
    Dir.mktmpdir('volcano-rubocop-config-') do |directory|
      config = File.join(directory, '.rubocop.yml')
      File.write(config, <<~YAML)
        inherit_from: #{root}/.rubocop.yml
        Metrics/CyclomaticComplexity:
          Include:
            - lib/volcano/guardrails_probe.rb
      YAML

      expect(inventory.metrics_apply_everywhere?(config:)).to be(false)
    end
  end

  it 'detects nested overrides and debt files' do
    Dir.mktmpdir('volcano-rubocop-inventory-') do |directory|
      Dir.mkdir(File.join(directory, 'nested'))
      File.write(File.join(directory, 'nested/.rubocop.yml'), "AllCops:\n  NewCops: disable\n")
      File.write(File.join(directory, '.rubocop_todo.yml'), "Style/Documentation:\n  Enabled: false\n")
      system('git', 'init', '--quiet', directory, exception: true)

      expect(described_class.new(directory).unexpected_configs)
        .to contain_exactly('nested/.rubocop.yml', '.rubocop_todo.yml')
    end
  end

  it 'finds versioned Ruby shebangs and ignores binary assets' do
    Dir.mktmpdir('volcano-rubocop-inventory-') do |directory|
      Dir.mkdir(File.join(directory, 'bin'))
      File.write(File.join(directory, 'bin/new-tool'), "#!/usr/bin/env ruby3.2\nputs 'hello'\n")
      File.binwrite(File.join(directory, 'asset.bin'), "\xFF\xFE".b)
      system('git', 'init', '--quiet', directory, exception: true)

      expect(described_class.new(directory).maintained_ruby).to eq(['bin/new-tool'])
    end
  end
end
