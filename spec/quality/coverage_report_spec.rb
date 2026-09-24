# frozen_string_literal: true

require 'tmpdir'
require_relative '../../maintainers/quality/coverage_report'

RSpec.describe CoverageReport do
  let(:directory) { Dir.mktmpdir('volcano-coverage-report-') }
  let(:gate) { described_class.new(directory, 'probe') }
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

  before do
    FileUtils.mkdir_p(File.join(directory, 'lib'))
    File.write(File.join(directory, 'lib/one.rb'), "ONE = 1\n")
    system('git', 'init', '--quiet', directory, exception: true)
    system('git', '-C', directory, 'add', 'lib/one.rb', exception: true)
  end

  after { FileUtils.remove_entry(directory) }

  def write_report(value)
    FileUtils.mkdir_p(File.dirname(report_path))
    File.write(report_path, value.is_a?(String) ? value : JSON.generate(value))
  end

  it 'accepts a complete fresh native report' do
    write_report(report)
    expect { gate.verify! }.not_to raise_error
  end

  it 'rejects a missing report' do
    expect { gate.verify! }.to raise_error(/Missing SimpleCov report/)
  end

  it 'rejects a formatted report that bypassed the threshold exit status' do
    report.fetch('total').fetch('branches')['missed'] = 1
    write_report(report)
    expect { gate.verify! }.to raise_error(/Incomplete branches coverage/)
  end

  it 'rejects a new runtime source absent from the report' do
    File.write(File.join(directory, 'lib/two.rb'), "TWO = 2\n")
    write_report(report)
    expect { gate.verify! }.to raise_error(%r{lib/two.rb})
  end

  it 'rejects a corrupt JSON report' do
    write_report('{')
    expect { gate.verify! }.to raise_error(JSON::ParserError)
  end
end
