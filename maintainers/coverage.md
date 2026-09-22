# Runtime coverage

`bundle exec rake quality:spec` runs the complete RSpec suite with SimpleCov.
The root `.simplecov` requires 100% line and branch coverage with zero missed
lines or branches. It includes every Ruby file under `lib/`, even files no test
loads. Only the generated client is excluded.

Coverage starts before Bundler loads the SDK. Each run writes HTML and JSON
reports under `reports/coverage/<run-id>/`; CI retains them and fails if the
reports are missing. Separate directories prevent previous runs from supplying
coverage to a later run.

The startup and clock probes run in child Ruby processes. Their shared
`spec/support/subprocess_coverage.rb` configuration records each child's result;
the parent merges those results before enforcing the thresholds. SimpleCov
handles measurement, merging, and failure status.

Use `bundle exec rspec <spec-file>` for focused feedback. Run the full quality
command before review.

References: [SimpleCov configuration](https://github.com/simplecov-ruby/simplecov/blob/v1.2.0/docs/Configuration.md),
[subprocess coordination](https://github.com/simplecov-ruby/simplecov/blob/v1.2.0/docs/Parallelism.md).
