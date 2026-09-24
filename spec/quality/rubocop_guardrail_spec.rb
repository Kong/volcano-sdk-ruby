# frozen_string_literal: true

require 'rubocop'
require 'tmpdir'

RSpec.describe RuboCop do
  let(:root) { File.expand_path('../..', __dir__) }

  def effective_policy(path)
    configuration = RuboCop::ConfigStore.new.for(path)
    {
      complexity: configuration.for_cop('Metrics/CyclomaticComplexity').fetch('Max'),
      complexity_enabled: configuration.for_cop('Metrics/CyclomaticComplexity').fetch('Enabled'),
      method_length: configuration.for_cop('Metrics/MethodLength').fetch('Max'),
      method_length_enabled: configuration.for_cop('Metrics/MethodLength').fetch('Enabled'),
      new_cops: configuration.for_all_cops.fetch('NewCops'),
      redundant_disables: configuration.for_cop('Lint/RedundantCopDisableDirective').fetch('Enabled'),
      verified_doubles: configuration.for_cop('RSpec/VerifiedDoubles').fetch('Enabled')
    }
  end

  it 'resolves the required guardrails for runtime and test files' do
    %w[lib/volcano.rb spec/spec_helper.rb].each do |path|
      expect(effective_policy(File.join(root, path))).to eq(
        complexity: 5, complexity_enabled: true,
        method_length: 10, method_length_enabled: true, new_cops: 'enable',
        redundant_disables: true, verified_doubles: true
      )
    end
  end

  it 'detects a raised complexity threshold in native RuboCop configuration' do
    Dir.mktmpdir('volcano-rubocop-policy-') do |directory|
      File.write(File.join(directory, '.rubocop.yml'), "Metrics/CyclomaticComplexity:\n  Max: 6\n")
      expect(effective_policy(File.join(directory, 'probe.rb'))[:complexity]).to eq(6)
    end
  end

  it 'detects a disabled complexity cop with its limit intact' do
    Dir.mktmpdir('volcano-rubocop-policy-') do |directory|
      File.write(File.join(directory, '.rubocop.yml'), "Metrics/CyclomaticComplexity:\n  Enabled: false\n  Max: 5\n")
      policy = effective_policy(File.join(directory, 'probe.rb'))
      expect(policy).to include(complexity: 5, complexity_enabled: false)
    end
  end
end
