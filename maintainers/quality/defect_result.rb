# frozen_string_literal: true

require 'json'

module Quality
  # Accept only a complete single-example report with a genuine assertion failure.
  class DefectResult
    ASSERTION_ERRORS = %w[RSpec::Expectations::ExpectationNotMetError RSpec::Mocks::MockExpectationError].freeze

    def initialize(path, status)
      @path = path
      @status = status
    end

    def outcome
      return 'timeout' if @status == :timeout

      report = JSON.parse(File.read(@path))
      return 'harness_error' unless complete?(report)

      classify(report.fetch('examples').first)
    rescue JSON::ParserError, Errno::ENOENT, KeyError, TypeError, NoMethodError
      'harness_error'
    end

    private

    def complete?(report)
      summary = report.fetch('summary')
      examples = report.fetch('examples')
      return false unless examples.is_a?(Array) && examples.length == 1

      consistent_counts?(summary, examples)
    end

    def consistent_counts?(summary, examples)
      expected = { 'example_count' => 1, 'pending_count' => 0, 'errors_outside_of_examples_count' => 0 }
      expected.all? { |key, value| summary.fetch(key) == value } &&
        summary.fetch('failure_count') == examples.count { |item| item.fetch('status') == 'failed' }
    end

    def classify(example)
      case [@status, example.fetch('status')]
      when [0, 'passed'] then 'passed'
      when [1, 'failed']
        ASSERTION_ERRORS.include?(example.fetch('exception').fetch('class')) ? 'detected' : 'harness_error'
      else 'harness_error'
      end
    end
  end
end
