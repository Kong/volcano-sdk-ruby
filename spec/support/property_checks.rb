# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'prop_check'

# Replays each property independently from the RSpec seed.
module PropertyChecks
  def check_property(generator, &)
    random = Random.new(RSpec.configuration.seed)
    seeded = PropCheck::Generator.new do |**options|
      generator.generate(**options, rng: random)
    end
    PropCheck.forall(seeded).with_config(n_runs: 200).check(&)
  end

  def self.record_failure(example)
    error = example.exception
    return unless error.respond_to?(:prop_check_info)

    FileUtils.mkdir_p('reports/property-failures')
    name = Digest::SHA256.hexdigest(example.id)
    File.write("reports/property-failures/#{name}.json", JSON.pretty_generate(failure_report(example)))
  end

  def self.failure_report(example)
    info = example.exception.prop_check_info
    {
      seed: RSpec.configuration.seed, example: example.id,
      original_input: info.fetch(:original_input).inspect,
      counterexample: info.fetch(:shrunken_input).inspect,
      successful_runs: info.fetch(:n_successful), shrink_steps: info.fetch(:n_shrink_steps),
      failure: example.exception.message
    }
  end
end

RSpec.configure do |config|
  config.include PropertyChecks
  config.after { |example| PropertyChecks.record_failure(example) }
end
