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

See the [RuboCop CLI reference](https://docs.rubocop.org/rubocop/1.90/usage/cli_reference.html).
