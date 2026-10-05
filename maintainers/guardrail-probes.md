# Native guardrail probes

The quality suite runs RuboCop against deliberately complex source at runtime
and spec paths. `--force-exclusion` makes a new `Exclude` entry remove an
offense from the probe, so that policy change fails the suite. The Steep probe
checks an invalid consumer against the shipped `sig/` tree and requires both
the argument-type and undeclared-method diagnostics. The fixture is never
included in the gem or the normal positive type target.

Two gaps need small checks around the native tools:

- [SimpleCov's thresholds](https://github.com/simplecov-ruby/simplecov/blob/v1.2.0/docs/Configuration.md)
  compare measured coverage with the configured minimum. A complete suite can
  still pass after someone lowers that minimum. The configuration spec reads
  SimpleCov's resolved settings in a fresh process and proves that a lowered
  threshold, broader filter, or changed ignore token fails.
- [RuboCop's CLI](https://docs.rubocop.org/rubocop/latest/usage/cli_reference.html)
  can inspect files and honor exclusions, but has no mode that forbids a
  `.rubocop_todo.yml` debt baseline. `NativeGate` checks that one tracked
  filename. RuboCop still owns all source linting and file discovery.
