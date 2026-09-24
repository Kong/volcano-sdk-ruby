# Runtime coverage

`bundle exec rake quality:spec` runs the complete RSpec suite with SimpleCov.
The root `.simplecov` requires 100% line and branch coverage with zero missed
lines or branches. It includes every Ruby file under `lib/`, even files no test
loads. Only the generated client is excluded.

`spec/quality/coverage_policy_spec.rb` verifies the effective SimpleCov settings
in the test process. Negative fixtures prove that lower thresholds, new runtime
exclusions, changed no-coverage tokens, disabled merge finalization, and a shared
result directory fail. A Rake task probe verifies distinct run IDs on successive
invocations.
SimpleCov enforces coverage but cannot lock its own configuration.

Ruby's Coverage library starts before Bundler evaluates the SDK gemspec;
SimpleCov then uses that measurement with the locked dependencies. Each run
writes HTML and JSON reports under `reports/coverage/<run-id>/`; CI retains them and fails if the
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
