# frozen_string_literal: true

require_relative '../../maintainers/quality/defect_result'
require 'tmpdir'
require 'fileutils'

RSpec.describe Quality::DefectResult do
  let(:directory) { Dir.mktmpdir('defect-result-spec-') }
  let(:path) { File.join(directory, 'result.json') }

  after { FileUtils.remove_entry(directory) }

  def report(status = 'passed', error = 'RSpec::Expectations::ExpectationNotMetError')
    { 'summary' => { 'example_count' => 1, 'failure_count' => status == 'failed' ? 1 : 0,
                     'pending_count' => 0, 'errors_outside_of_examples_count' => 0 },
      'examples' => [{ 'status' => status, 'exception' => { 'class' => error } }] }
  end

  def outcome(payload, status)
    File.write(path, JSON.generate(payload))
    described_class.new(path, status).outcome
  end

  it 'accepts a complete passing baseline' do
    expect(outcome(report, 0)).to eq('passed')
  end

  described_class::ASSERTION_ERRORS.each do |error|
    it "counts a failed assertion from #{error} as detection" do
      expect(outcome(report('failed', error), 1)).to eq('detected')
    end
  end

  it 'does not count an unexpected runtime error as detection' do
    expect(outcome(report('failed', 'NoMethodError'), 1)).to eq('harness_error')
  end

  [nil, 2, 137].each do |status|
    it "rejects abnormal process status #{status.inspect}" do
      expect(outcome(report('failed'), status)).to eq('harness_error')
    end
  end

  it 'reports timeouts separately even if a report exists' do
    expect(outcome(report('failed'), :timeout)).to eq('timeout')
  end

  it 'rejects empty test discovery' do
    expect(outcome(report.merge('examples' => []), 1)).to eq('harness_error')
  end

  %w[example_count failure_count pending_count errors_outside_of_examples_count].each do |field|
    it "rejects inconsistent #{field}" do
      payload = report('failed')
      payload.fetch('summary')[field] += 1
      expect(outcome(payload, 1)).to eq('harness_error')
    end
  end

  it 'rejects skipped or pending examples' do
    expect(outcome(report('pending'), 0)).to eq('harness_error')
  end

  it 'rejects a passing report from a failed process' do
    expect(outcome(report, 1)).to eq('harness_error')
  end

  it 'rejects a failure report from a successful process' do
    expect(outcome(report('failed'), 0)).to eq('harness_error')
  end

  it 'rejects missing reports' do
    expect(described_class.new(path, 1).outcome).to eq('harness_error')
  end

  [nil, {}, { 'summary' => {} }, { 'examples' => false }].each do |payload|
    it "rejects malformed reports #{payload.inspect}" do
      expect(outcome(payload, 1)).to eq('harness_error')
    end
  end

  it 'rejects invalid JSON' do
    File.write(path, '{')
    expect(described_class.new(path, 1).outcome).to eq('harness_error')
  end
end
