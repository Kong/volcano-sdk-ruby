# frozen_string_literal: true

# Observe results without replacing RSpec's normal formatter or failure reports.
class TestIntegrity
  def initialize
    @started = Set.new
    @expected = Set.new
    @violations = []
  end

  def start(_notification)
    return unless ENV['VOLCANO_REQUIRE_FULL_SUITE'] == '1'

    @expected = RSpec.world.all_examples.to_set(&:id)
  end

  def example_started(notification)
    example = notification.example
    @violations << "repeated example: #{example.id}" unless @started.add?(example.id)
    return unless example.metadata.keys.intersect?(%i[focus retry])

    @violations << "focused or retried example: #{example.id}"
  end

  def example_pending(notification)
    @violations << "pending or skipped example: #{notification.example.id}"
  end

  def verify!
    missing = @expected - @started
    @violations << "filtered or unexecuted examples: #{missing.to_a.join(', ')}" unless missing.empty?
    return if @violations.empty?

    raise "Incomplete test run: #{@violations.uniq.join(', ')}"
  end
end

RSpec.configure do |config|
  integrity = TestIntegrity.new
  config.reporter.register_listener(integrity, :start, :example_started, :example_pending)
  config.after(:suite) { integrity.verify! }
  config.fail_if_no_examples = true
  config.order = :random
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
