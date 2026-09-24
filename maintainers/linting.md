# Ruby linting

`bundle exec rake quality:lint` runs RuboCop with the root `.rubocop.yml` and
`.rubocop` options. Direct `bundle exec rubocop` commands use the same settings.
The native `Style/DisableCopsWithinSourceCodeDirective` rule rejects suppression
directives except the cops with reviewed line-scoped exceptions. This rule
cannot suppress itself. `Lint/RedundantCopDisableDirective` rejects unused
suppressions, and `--raise-cop-error` makes internal cop failures fail the command.

RuboCop's `AllowedCops` option cannot restrict an exception to an exact source
line. `spec/rubocop/directive_comment_spec.rb` uses RuboCop's parser and target
inventory to require exactly the eight approved inline directives. It also runs
the native CLI with `--ignore-disable-comments` and requires exactly the eight
documented diagnostics. Added, broadened, and unused exceptions fail the gate.
The [native directive rules](https://docs.rubocop.org/rubocop/1.90/usage/source_code_directives.html)
keep the exception itself in the tool's standard format; the spec covers only
the source-scope limitation.

Native `AllCops/Include` configuration adds package smoke scripts under
`.github/scripts` without replacing RuboCop's default file discovery.
Configuration regression specs invoke the actual CLI and verify that it rejects
suppressed offenses in runtime and test paths.
Before running RuboCop, `quality:lint` compares Git-tracked handwritten Ruby
files with RuboCop's `--list-target-files` result. Source recognition uses the
pinned RuboCop defaults, including Ruby executables, manifests, and task files.
The gate also rejects nested configurations outside the generated client.
Cop-specific `Include` and `Exclude` still require policy review; target
discovery cannot prove which cops ran on each file.

See the [RuboCop CLI reference](https://docs.rubocop.org/rubocop/1.90/usage/cli_reference.html).

## Source discovery

Steep's native `check` paths select files but do not fail when a new source
file matches no target. The SDK needs separate targets with different signatures,
so a single catch-all target cannot safely replace their file lists.
`spec/steep/project_source_inventory_spec.rb` compares `steep project --print`
with Git's runtime inventory. A temporary runtime file outside every Steep
target made that spec fail while the native type check still passed.

Steep also permits diagnostic severity overrides. Its native project parser
provides the effective settings used by `spec/steep/project_diagnostic_policy_spec.rb`;
every target and nested group must retain `Steep::Diagnostic::Ruby.all_error`.
This catches configuration downgrades while Steep remains the type checker.
Steep's [ignore comments](https://github.com/soutaro/steep/blob/v1.10.0/lib/steep/ast/ignore.rb)
can suppress errors even in that mode, and the native checker has no setting to
forbid them. `Volcano/TypeSuppression` rejects those directives through RuboCop's
parsed comments. Regression specs cover inline and block directives in runtime
and test files while allowing fixture strings.

Native SimpleCov and RuboCop enforce their configured limits but do not reject
a policy edit that lowers those limits. `spec/simple_cov_policy_spec.rb` and
`spec/rubocop/config_store_policy_spec.rb` inspect the effective native settings
for runtime files. Temporary 99% coverage limits, an added runtime exclusion,
and a higher complexity cap each made these specs fail. The native gate
separately rejects nested RuboCop configuration. The tools still measure
coverage and lint the code.

## Dynamic method declarations

Steep checks `@dynamic` names against RBS but does not reject declarations that
are no longer needed. The exact namespace/method inventory in
[steep-dynamic-methods.json](steep-dynamic-methods.json) is paired with the
rationales in [quality-exceptions.md](quality-exceptions.md). RuboCop's parser
checks their source scopes, and both native Steep targets run against a temporary
copy with those annotations removed. The resulting missing-method set must
match the inventory exactly. Added, missing, and unnecessary annotations fail.
Steep exports structured diagnostics only inside the temporary directory; its
pinned API and diagnostic format keep the comparison exact. No report is saved
as a repository baseline.

This check found 132 unnecessary names on classes reopened by multiple RBS
signatures; their annotations were removed. The remaining 244 names each have
a corresponding native diagnostic. Runtime method bodies and signatures stay
checked in the ordinary all-error runs; no diagnostic baseline is used there.

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

## Correctness profile

All native `Lint` cops and new cops are enabled. The five optional correctness
cops cover constant resolution, heredoc call position, numeric conversion,
shadowed variables, and unused private methods. Formatting retains RuboCop's
standard defaults plus the existing Performance, Rake, and RSpec configuration.
The all-style experiment produced conflicting formatter rules and unsafe changes
to string-keyed JSON and missing-key behavior; the correctness profile was
human-approved on 2026-09-24.

`UseProjectIndex` and pinned Rubydex add native cross-file analysis. The index
is experimental, so exact reviewed limitations remain in
[quality-exceptions.md](quality-exceptions.md). Native configuration regression
specs require every `Lint` cop and the project index to stay enabled. Test-only
aliases live under `SpecSupport`; RSpec's native `CustomTransform` omits that
prefix when checking filenames, preserving the runtime module's path.

References: [RuboCop configuration](https://docs.rubocop.org/rubocop/1.90/configuration.html),
[project index](https://docs.rubocop.org/rubocop/1.90/usage/project_index.html),
[optional style semantics](https://docs.rubocop.org/rubocop/1.90/cops_style.html).
[Standard Ruby](https://github.com/standardrb/standard) and
[Rails](https://github.com/rails/rails/blob/main/.rubocop.yml) also use curated
native style profiles. We retain the existing profile rather than adding another
formatter or a second lint runner.
