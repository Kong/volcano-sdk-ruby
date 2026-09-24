# frozen_string_literal: true

require 'open3'
require 'rubocop'
require 'tmpdir'

class QualityPolicyInventory
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

  def maintained_ruby
    files.grep(/\.rb\z/).reject { |path| path.start_with?('lib/volcano/generated/') }
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
    [settings.fetch('Metrics/CyclomaticComplexity').fetch('Max'),
     settings.fetch('Metrics/MethodLength').fetch('Max'),
     settings.fetch('AllCops').fetch('NewCops')]
  end
end

RSpec.describe QualityPolicyInventory do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:inventory) { described_class.new(root) }

  it 'keeps RuboCop configuration at the repository root without debt files' do
    expect(inventory.nested_rubocop_configs).to be_empty
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
end
