# frozen_string_literal: true

require 'tmpdir'
require_relative '../../maintainers/quality/native_gate'

RSpec.describe NativeGate do
  let(:directory) { Dir.mktmpdir('volcano-native-gate-') }
  let(:report_path) { File.join(directory, 'reports/coverage/probe/coverage.json') }
  let(:report) do
    {
      'total' => {
        'lines' => { 'total' => 1, 'covered' => 1, 'missed' => 0 },
        'branches' => { 'total' => 1, 'covered' => 1, 'missed' => 0 }
      },
      'coverage' => { 'lib/one.rb' => {} }
    }
  end

  before { system('git', 'init', '--quiet', directory, exception: true) }

  after { FileUtils.remove_entry(directory) }

  def write_report(value)
    FileUtils.mkdir_p(File.dirname(report_path))
    File.write(report_path, value.is_a?(String) ? value : JSON.generate(value))
  end

  def add_runtime_source(name)
    FileUtils.mkdir_p(File.join(directory, 'lib'))
    File.write(File.join(directory, "lib/#{name}.rb"), "#{name.upcase} = 1\n")
    system('git', '-C', directory, 'add', "lib/#{name}.rb", exception: true)
  end

  it 'checks the tracked files against native RuboCop discovery' do
    expect { described_class.verify_lint_targets!(File.expand_path('../..', __dir__)) }.not_to raise_error
  end

  it 'rejects Ruby sources excluded from the lint task' do
    File.write(File.join(directory, '.rubocop.yml'), "AllCops:\n  Exclude:\n    - hidden.rake\n")
    File.write(File.join(directory, 'hidden.rake'), "task(:hidden) {}\n")
    system('git', '-C', directory, 'add', '.', exception: true)

    expect { described_class.verify_lint_targets!(directory) }.to raise_error(/hidden.rake/)
  end

  it 'rejects nested RuboCop configuration' do
    Dir.mkdir(File.join(directory, 'nested'))
    File.write(File.join(directory, 'nested/.rubocop.yml'), "AllCops:\n  NewCops: disable\n")
    system('git', '-C', directory, 'add', '.', exception: true)

    expect { described_class.verify_lint_targets!(directory) }.to raise_error(/Nested RuboCop configuration/)
  end

  it 'rejects a tracked RuboCop debt baseline' do
    File.write(File.join(directory, '.rubocop_todo.yml'), "Metrics/CyclomaticComplexity:\n  Enabled: false\n")
    system('git', '-C', directory, 'add', '.', exception: true)

    expect { described_class.verify_lint_targets!(directory) }.to raise_error(/RuboCop debt baseline/)
  end

  it 'accepts a fresh full-coverage report' do
    add_runtime_source('one')
    write_report(report)
    expect { described_class.verify_coverage!(directory, 'probe') }.not_to raise_error
  end

  it 'rejects a missing report' do
    expect { described_class.verify_coverage!(directory, 'probe') }.to raise_error(/Missing SimpleCov report/)
  end

  it 'rejects a formatted report that bypassed coverage threshold failure' do
    report.fetch('total').fetch('branches')['missed'] = 1
    write_report(report)
    expect { described_class.verify_coverage!(directory, 'probe') }.to raise_error(/Incomplete branches coverage/)
  end

  it 'rejects a runtime source absent from the report' do
    add_runtime_source('two')
    write_report(report)
    expect { described_class.verify_coverage!(directory, 'probe') }.to raise_error(%r{lib/two.rb})
  end

  it 'rejects a malformed report' do
    write_report('{')
    expect { described_class.verify_coverage!(directory, 'probe') }.to raise_error(JSON::ParserError)
  end
end
