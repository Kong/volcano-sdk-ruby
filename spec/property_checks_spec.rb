# frozen_string_literal: true

require 'open3'
require 'tmpdir'

RSpec.describe PropertyChecks do
  def run_property_fixture(directory)
    path = File.join(directory, 'fixture_spec.rb')
    File.write(path, property_fixture_source)
    Open3.capture3(
      Gem.ruby, Gem.bin_path('rspec-core', 'rspec'), '--options', File::NULL,
      '--require', File.expand_path('support/property_checks.rb', __dir__),
      '--seed', '12345', path, chdir: directory
    )
  end

  def property_fixture_source
    <<~RUBY
      RSpec.describe(String) do
        it('fails with a counterexample') do
          check_property(PropCheck::Generators.positive_integer) do |number|
            expect(number).to eq(-1)
          end
        end
      end
    RUBY
  end

  it 'fails the suite and preserves a replayable seed and minimized counterexample' do
    Dir.mktmpdir('volcano-property-policy-') do |directory|
      output, errors, status = run_property_fixture(directory)
      reports = Dir.glob(File.join(directory, 'reports/property-failures/*.json'))
      expect(status.success?).to be(false), errors
      expect(output).to include('1 example, 1 failure', 'Randomized with seed 12345')
      expect(reports.length).to eq(1)
      report = JSON.parse(File.read(reports.fetch(0)))
      expect(report).to include('seed' => 12_345, 'counterexample' => '1', 'successful_runs' => 0)
      expect(report.fetch('failure')).to include('Failed on:')
    end
  end

  it 'replays the same generated inputs from the same RSpec seed' do
    generator = PropCheck::Generators.printable_string
    first = []
    second = []
    check_property(generator) { |value| first << value }
    check_property(generator) { |value| second << value }
    expect(first.length).to eq(200)
    expect(first.uniq.length).to be > 1
    expect(second).to eq(first)
  end
end
