# frozen_string_literal: true

SimpleCov.configure do
  cover 'lib/**/*.rb'
  skip '/lib/volcano/generated/'
  coverage :line, minimum: 100, maximum_missed: 0
  coverage :branch, minimum: 100, maximum_missed: 0
  merging true
  coverage_dir "reports/coverage/#{SimpleCov.run_id}"
  deprecations :raise
end
