# frozen_string_literal: true

require 'open3'
require 'tmpdir'

RSpec.describe TestIntegrity do
  def run_spec(source)
    Dir.mktmpdir('volcano-spec-integrity-') do |directory|
      path = File.join(directory, 'fixture_spec.rb')
      File.write(path, source)
      Open3.capture3(
        Gem.ruby, Gem.bin_path('rspec-core', 'rspec'), '--options', File::NULL,
        '--require', File.expand_path('support/test_integrity.rb', __dir__),
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
end
