# frozen_string_literal: true

require 'open3'
require 'tmpdir'

RSpec.describe TestIntegrity do
  def run_spec(source)
    Dir.mktmpdir('volcano-spec-integrity-') do |directory|
      path = File.join(directory, 'fixture_spec.rb')
      File.write(path, source)
      Open3.capture3(
        { 'VOLCANO_REQUIRE_FULL_SUITE' => '1' },
        Gem.ruby, Gem.bin_path('rspec-core', 'rspec'), '--options', File::NULL,
        '--require', File.expand_path('support/test_integrity.rb', __dir__),
        '--failure-exit-code', '1', '--error-exit-code', '1',
        '--seed', '12345', path, chdir: directory
      )
    end
  end

  it 'accepts a complete passing suite' do
    output, errors, status = run_spec("RSpec.describe(String) { it('works') { expect('ok').to eq('ok') } }")

    expect(status.success?).to be(true), errors
    expect(output).to include('1 example, 0 failures', 'Randomized with seed 12345')
  end

  {
    'pending declarations' => "it('unfinished')",
    'skipped examples' => "xit('skipped') { expect(true).to be(true) }",
    'runtime skips' => "it('skipped') { skip 'unfinished' }",
    'runtime pending' => "it('pending') { pending 'unfinished'; expect(true).to be(false) }",
    'focused examples' => "fit('focused') { expect(true).to be(true) }",
    'retry metadata' => "it('retried', retry: 2) { expect(true).to be(true) }",
    'repeated reports' => "it('repeated') { RSpec.configuration.reporter.example_started(RSpec.current_example) }"
  }.each do |behavior, body|
    it "rejects #{behavior}" do
      output, _errors, status = run_spec("RSpec.describe(String) { #{body} }")

      expect(status.success?).to be(false)
      expect(output).to include('Incomplete test run:')
    end
  end

  it 'rejects an empty suite' do
    output, _errors, status = run_spec('RSpec.describe(String) {}')

    expect(status.success?).to be(false)
    expect(output).to include('No examples found.')
  end

  {
    'inclusion filters' => 'config.filter_run_including(gate_probe: true)',
    'exclusion filters' => 'config.filter_run_excluding(gate_probe: false)',
    'matching filters' => 'config.filter_run_when_matching(gate_probe: true)'
  }.each do |behavior, configuration|
    it "rejects #{behavior} that leave a passing subset" do
      output, _errors, status = run_spec(<<~RUBY)
        RSpec.configure { |config| #{configuration} }
        RSpec.describe String do
          it('passes', gate_probe: true) { expect(true).to be(true) }
          it('must run', gate_probe: false) { expect(true).to be(false) }
        end
      RUBY

      expect(status.success?).to be(false)
      expect(output).to include('filtered or unexecuted examples:')
    end
  end

  it 'rejects partial doubles of methods that do not exist' do
    output, _errors, status = run_spec(
      "RSpec.describe(String) { it('verifies') { allow(Object.new).to receive(:invented_method) } }"
    )

    expect(status.success?).to be(false)
    expect(output).to include('does not implement: invented_method')
  end

  it 'preserves a real assertion failure' do
    output, _errors, status = run_spec("RSpec.describe(String) { it('fails') { expect(true).to be(false) } }")

    expect(status.success?).to be(false)
    expect(output).to include('1 example, 1 failure')
  end

  {
    'assertion failures' => "it('fails') { expect(true).to be(false) }",
    'suite errors' => <<~RUBY
      RSpec.configure { |config| config.before(:suite) { raise 'setup failed' } }
      it('works') { expect(true).to be(true) }
    RUBY
  }.each do |behavior, body|
    it "keeps #{behavior} nonzero when a spec configures successful exit codes" do
      output, _errors, status = run_spec(<<~RUBY)
        RSpec.configure do |config|
          config.failure_exit_code = 0
          config.error_exit_code = 0
        end
        RSpec.describe(String) { #{body} }
      RUBY

      expect(status.exitstatus).to eq(1), output
    end
  end
end
