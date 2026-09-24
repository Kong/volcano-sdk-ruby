# frozen_string_literal: true

require 'open3'
require 'rubocop'
require 'tmpdir'

class QualityPolicyInventory
  RUBY_ENTRYPOINTS = %w[.simplecov Gemfile Rakefile Steepfile volcano-sdk.gemspec bin/check-defects].freeze

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

  def nested_rubocop_configs
    files.grep(%r{(?:\A|/)\.rubocop(?:_todo)?(?:\.yml)?\z}) -
      %w[.rubocop .rubocop.yml lib/volcano/generated/.rubocop.yml]
  end

  def inherited_rubocop_configs(config: File.join(@root, '.rubocop.yml'))
    settings = RuboCop::ConfigLoader.load_yaml_configuration(config)
    settings.keys & %w[inherit_from inherit_gem]
  end

  def lint_options_locked?
    File.binread(File.join(@root, '.rubocop')) == "--ignore-disable-comments\n--raise-cop-error\n"
  end

  def maintained_ruby
    paths = files.select { |path| path.end_with?('.rb') || RUBY_ENTRYPOINTS.include?(path) || ruby_shebang?(path) }
    paths.reject! { |path| path.start_with?('lib/volcano/generated/') }
    paths
  end

  def ruby_shebang?(path)
    return false unless File.file?(File.join(@root, path))

    File.binread(File.join(@root, path), 128).split("\n", 2).first.match?(/\A#!.*\bruby(?:\s|\z)/n)
  end

  def missing_lint_targets(config: nil)
    arguments = [Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--list-target-files']
    arguments.push('--config', config) if config
    output, error, status = Open3.capture3(*arguments, chdir: @root)
    raise error unless status.success?

    maintained_ruby - output.lines.map { |line| line.strip.delete_prefix('./') }
  end

  def lint_limits(config: File.join(@root, '.rubocop.yml'))
    settings = RuboCop::ConfigLoader.load_file(config)
    [cop_limit(settings, 'Metrics/CyclomaticComplexity'),
     cop_limit(settings, 'Metrics/MethodLength'), settings.fetch('AllCops').fetch('NewCops')]
  end

  def cop_limit(settings, name)
    cop = settings.fetch(name)
    return unless unrestricted_cop?(cop)

    cop.fetch('Max')
  end

  def unrestricted_cop?(cop)
    cop.fetch('Enabled', true) == true && cop.fetch('Exclude', []).empty? &&
      cop.fetch('AllowedMethods', []).empty? && cop.fetch('AllowedPatterns', []).empty? &&
      !cop.key?('Include')
  end
end

RSpec.describe QualityPolicyInventory do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:inventory) { described_class.new(root) }

  it 'keeps RuboCop configuration at the repository root without debt files' do
    expect(inventory.nested_rubocop_configs).to be_empty
    expect(inventory.inherited_rubocop_configs).to be_empty
    expect(inventory.lint_options_locked?).to be(true)
  end

  it 'includes every maintained Ruby file in native RuboCop discovery' do
    expect(inventory.missing_lint_targets).to be_empty
  end

  it 'keeps the core RuboCop limits and new cops enabled' do
    expect(inventory.lint_limits).to eq([5, 10, 'enable'])
  end

  it 'detects a nested RuboCop override and a debt baseline' do
    Dir.mktmpdir('volcano-policy-inventory-') do |directory|
      Dir.mkdir(File.join(directory, 'nested'))
      File.write(File.join(directory, 'nested/.rubocop.yml'), "AllCops:\n  NewCops: disable\n")
      File.write(File.join(directory, '.rubocop_todo.yml'), "Style/Documentation:\n  Enabled: false\n")
      system('git', 'init', '--quiet', directory, exception: true)

      probe = described_class.new(directory)
      expect(probe.nested_rubocop_configs).to contain_exactly('nested/.rubocop.yml', '.rubocop_todo.yml')
    end
  end

  it 'detects a maintained source file excluded by a nested RuboCop configuration' do
    Dir.mktmpdir('volcano-policy-config-') do |directory|
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

  it 'detects a raised complexity limit in a RuboCop override' do
    Dir.mktmpdir('volcano-policy-config-') do |directory|
      config = File.join(directory, '.rubocop.yml')
      File.write(config, <<~YAML)
        inherit_from: #{root}/.rubocop.yml
        Metrics/CyclomaticComplexity:
          Max: 6
      YAML

      expect(inventory.lint_limits(config:)).not_to eq([5, 10, 'enable'])
    end
  end

  it 'detects a disabled or file-excluded metrics cop' do
    Dir.mktmpdir('volcano-policy-config-') do |directory|
      disabled = File.join(directory, 'disabled.yml')
      excluded = File.join(directory, 'excluded.yml')
      File.write(disabled, "inherit_from: #{root}/.rubocop.yml\nMetrics/CyclomaticComplexity:\n  Enabled: false\n")
      File.write(excluded, <<~YAML)
        inherit_from: #{root}/.rubocop.yml
        Metrics/MethodLength:
          Exclude:
            - #{root}/lib/volcano/transport.rb
      YAML

      expect(inventory.lint_limits(config: disabled)).not_to eq([5, 10, 'enable'])
      expect(inventory.lint_limits(config: excluded)).not_to eq([5, 10, 'enable'])
    end
  end

  it 'rejects an options file that disables required cops' do
    Dir.mktmpdir('volcano-policy-options-') do |directory|
      File.write(File.join(directory, '.rubocop'), "--except Metrics/CyclomaticComplexity,Metrics/MethodLength\n")

      expect(described_class.new(directory).lint_options_locked?).to be(false)
    end
  end

  it 'detects cop-specific include narrowing' do
    Dir.mktmpdir('volcano-policy-config-') do |directory|
      config = File.join(directory, '.rubocop.yml')
      File.write(config, <<~YAML)
        inherit_from: #{root}/.rubocop.yml
        Metrics/CyclomaticComplexity:
          Include:
            - no-such-source/**/*.rb
      YAML

      expect(inventory.lint_limits(config:)).not_to eq([5, 10, 'enable'])
    end
  end

  it 'detects an inherited nested policy file even without a conventional RuboCop name' do
    Dir.mktmpdir('volcano-policy-config-') do |directory|
      config = File.join(directory, '.rubocop.yml')
      File.write(config, "inherit_from: config/rubocop_todo.yml\n")

      expect(inventory.inherited_rubocop_configs(config:)).to eq(['inherit_from'])
    end
  end

  it 'keeps extensionless Ruby entrypoints in lint discovery' do
    expect(inventory.maintained_ruby).to include(*described_class::RUBY_ENTRYPOINTS)
    expect(inventory.missing_lint_targets).to be_empty
  end

  it 'detects a newly added extensionless Ruby script by its interpreter' do
    Dir.mktmpdir('volcano-policy-inventory-') do |directory|
      Dir.mkdir(File.join(directory, 'bin'))
      File.write(File.join(directory, 'bin/new-tool'), "#!/usr/bin/env ruby\nputs 'hello'\n")
      system('git', 'init', '--quiet', directory, exception: true)

      expect(described_class.new(directory).maintained_ruby).to include('bin/new-tool')
    end
  end

  it 'ignores binary assets during Ruby shebang discovery' do
    Dir.mktmpdir('volcano-policy-inventory-') do |directory|
      File.binwrite(File.join(directory, 'asset.bin'), "\xFF\xFE".b)
      system('git', 'init', '--quiet', directory, exception: true)

      expect(described_class.new(directory).maintained_ruby).to be_empty
    end
  end
end
