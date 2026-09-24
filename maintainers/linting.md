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
suppressed offenses in runtime and test paths.
Before running RuboCop, `quality:lint` compares Git-tracked handwritten Ruby
files with RuboCop's `--list-target-files` result. Source recognition uses the
pinned RuboCop defaults, including Ruby executables, manifests, and task files.
The gate also rejects nested configurations outside the generated client.
It rejects `.rubocop_todo.yml` debt baselines anywhere in the repository.
Cop-specific `Include` and `Exclude` still require policy review; target
discovery cannot prove which cops ran on each file.

`spec/quality/rubocop_guardrail_spec.rb` checks RuboCop's resolved settings for
runtime and test files, including cyclomatic complexity at most five, ten-line
method limit, enabled new cops, redundant-directive checks, and verifying doubles.

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
