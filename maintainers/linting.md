# Ruby linting

`bundle exec rake quality:lint` runs RuboCop with the root `.rubocop.yml` and
`.rubocop` options. Direct `bundle exec rubocop` commands use the same settings.
The native `--ignore-disable-comments` option keeps violations visible even
when source comments try to disable a cop. RuboCop's
`Lint/RedundantCopDisableDirective` rejects unused suppressions, and
`--raise-cop-error` makes internal cop failures fail the command.

Native `AllCops/Include` configuration adds package smoke scripts under
`.github/scripts` without replacing RuboCop's default file discovery.
Configuration regression specs invoke the actual CLI and verify that it rejects
suppressed offenses in runtime and test paths. They also require the complexity
and method-length cops to report deliberately invalid source through the
effective CLI options and configuration.
The options file is pinned so a future `--except` cannot silently remove a cop.

`spec/quality/rubo_cop_source_inventory_spec.rb` compares tracked Ruby files
and extensionless Ruby entrypoints with RuboCop's native `--list-target-files`
output. It rejects nested overrides, inherited configurations, disabled cops,
and debt files.
The generated client's sole nested configuration is verified by
`quality:generated` against regenerated output. RuboCop can list inspected files
but cannot require that every tracked source appears in that list.

See the [RuboCop CLI reference](https://docs.rubocop.org/rubocop/1.90/usage/cli_reference.html).

## Coverage directives

`Volcano/CoverageSuppression` rejects SimpleCov skip directives in Ruby comments,
including inline directives and legacy `:nocov:` comments. Fixture strings and
heredocs remain valid. The normal RuboCop command loads this local cop; it adds
no runner or dependencies. CLI regression specs exercise both runtime and test
paths, including attempts to suppress the cop itself.

SimpleCov supports skip comments but has no option to forbid them, and RuboCop's
built-in directive cops only govern RuboCop directives. This is the limited gap
covered by the extension. [RuboCop extensions](https://docs.rubocop.org/rubocop/1.90/development.html)
provide parsed comments and native diagnostics. [Semgrep regex rules](https://docs.semgrep.dev/writing-rules/rule-syntax)
and [pre-commit pygrep](https://pre-commit.com/#pygrep) could scan the text but
would add another toolchain and need extra handling to distinguish Ruby comments
from fixture strings. [SimpleCov documents the supported directives](https://github.com/simplecov-ruby/simplecov/blob/v1.2.0/docs/Configuration.md).
