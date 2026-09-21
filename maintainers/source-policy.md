# Source policy

`bundle exec rake quality` checks tracked and new, non-ignored Ruby sources
against RuboCop's discovered targets. This includes conventional Ruby filenames
and executable Ruby scripts without extensions. A missing target fails the gate.

Keep configuration in the root `.rubocop.yml`. Inherited configurations, nested
overrides, debt baselines, repository symlinks, and inline lint or coverage
suppressions fail the gate. Cop-level and department-level file exclusions fail
unless they match these test conventions:

| Rule | Scope | Reason |
| --- | --- | --- |
| `Metrics/BlockLength` | `spec/**/*`, `features/step_definitions/**/*` | RSpec groups and shared scenario definitions are DSL blocks, not runtime functions. Method and cyclomatic limits still apply. |
| `Style/Documentation` | `spec/**/*`, `features/**/*` | Example and scenario prose documents test behavior. Runtime documentation remains required. |

`Quality::CopScopePolicy` records these exact scopes. Adding or broadening one is
a policy change. Existing violations are not an exception category.

The generated client and its generated configurations under
`lib/volcano/generated/` are checked by regeneration comparison instead. Handwritten source belongs outside that directory. A tracked
Ruby file under `vendor/` is still maintained source unless a separate provenance
policy explicitly establishes otherwise; the directory name is not an exemption.
