# frozen_string_literal: true

require 'open3'
require 'rubocop'

RSpec.describe RuboCop::Cop::Metrics::CyclomaticComplexity do
  def lint_method(conditions)
    source = "def decision(value)\n#{conditions.map { |n| "  return #{n} if value == #{n}\n" }.join}end\n"
    Open3.capture3(
      Gem.ruby, Gem.bin_path('rubocop', 'rubocop'), '--config', File.expand_path('../../../../.rubocop.yml', __dir__),
      '--only', 'Metrics/CyclomaticComplexity', '--format', 'simple', '--stdin', 'lib/volcano/complexity_fixture.rb',
      stdin_data: source
    )
  end

  it 'accepts a method at the complexity limit' do
    output, errors, status = lint_method(1..4)

    expect(status.success?).to be(true), output + errors
    expect(output).to include('no offenses detected')
  end

  it 'rejects a method above the complexity limit' do
    output, errors, status = lint_method(1..5)

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Cyclomatic complexity for decision is too high. [6/5]')
  end
end
