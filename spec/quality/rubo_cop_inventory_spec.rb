# frozen_string_literal: true

require 'tmpdir'
require_relative '../../maintainers/quality/rubocop_inventory'

RSpec.describe RuboCopInventory do
  let(:root) { File.expand_path('../..', __dir__) }

  it 'includes every tracked handwritten Ruby source in native lint discovery' do
    expect(described_class.new(root).missing_sources).to be_empty
  end

  it 'keeps one root RuboCop configuration' do
    expect(described_class.new(root).nested_configs).to be_empty
  end

  it 'rejects excluded Ruby files, including executables, and a nested override' do
    Dir.mktmpdir('volcano-rubocop-inventory-') do |directory|
      File.write(File.join(directory, '.rubocop.yml'),
                 "AllCops:\n  Exclude:\n    - hidden.rb\n    - check\n    - Rakefile\n")
      File.write(File.join(directory, 'hidden.rb'), "def hidden; true; end\n")
      File.write(File.join(directory, 'check'), "#!/usr/bin/env ruby\nputs 'hidden'\n")
      File.write(File.join(directory, 'Rakefile'), "task(:hidden) {}\n")
      Dir.mkdir(File.join(directory, 'nested'))
      File.write(File.join(directory, 'nested/.rubocop.yml'), "AllCops:\n  NewCops: disable\n")
      system('git', 'init', '--quiet', directory, exception: true)
      system('git', '-C', directory, 'add', '.', exception: true)

      inventory = described_class.new(directory)
      expect(inventory.missing_sources).to eq(%w[Rakefile check hidden.rb])
      expect(inventory.nested_configs).to eq(['nested/.rubocop.yml'])
    end
  end
end
