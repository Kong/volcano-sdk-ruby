# frozen_string_literal: true

require 'simplecov'

module CoveragePolicy
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  def self.valid?(root)
    thresholds? && runtime_scope?(root) && exclusions? && isolation? && run_identity?
  end

  def self.thresholds?
    SimpleCov.minimum_coverage == { line: 100, branch: 100 } &&
      SimpleCov.maximum_missed == { line: 0, branch: 0 }
  end

  def self.runtime_scope?(root)
    SimpleCov.root == root && SimpleCov.cover_filters.map(&:filter_argument) == ['lib/**/*.rb']
  end

  def self.exclusions?
    filters = SimpleCov.filters.map(&:filter_argument)
    return false unless filters.length == 5

    [filters[0], filters[1], filters[3], filters[4]] ==
      ['/vendor/bundle/', /\A\..*/, %r{\A(test|features|spec|autotest)/}, '/lib/volcano/generated/'] &&
      filters[2].source_location.first.start_with?(Gem.loaded_specs.fetch('simplecov').full_gem_path)
  end

  def self.isolation?
    SimpleCov.coverage_dir == "reports/coverage/#{SimpleCov.run_id}" && SimpleCov.merging &&
      SimpleCov.finalize_merge? && suppression_policy?
  end

  def self.suppression_policy?
    SimpleCov.current_nocov_token == 'nocov' && SimpleCov::Deprecation.mode == :raise
  end

  def self.run_identity?
    return true unless ENV['VOLCANO_REQUIRE_FULL_SUITE'] == '1'

    run_id = ENV.fetch('SIMPLECOV_RUN_ID')
    run_id == SimpleCov.run_id && run_id.match?(UUID)
  end
end
