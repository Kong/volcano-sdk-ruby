# Test integrity

RSpec owns discovery, execution, randomization, mock verification, and reporting.
Its `fail_if_no_examples` setting rejects an empty run, but accepts a nonempty
subset selected by an [inclusion filter](https://rspec.info/features/3-13/rspec-core/filtering/inclusion-filters/).
RSpec 3.13 has no option to fail when a filter omits loaded examples.

The existing `TestIntegrity` result listener fills that gap. At the `start`
notification it snapshots loaded example IDs from `RSpec.world.all_examples`,
then compares them with `example_started` notifications after the suite. This
uses an internal RSpec registry; the locked RSpec version and subprocess
regressions protect that integration. It also rejects pending, skipped, focused,
and repeated examples. Native RSpec reporting and exit failures remain intact.

`quality:spec` sets `VOLCANO_REQUIRE_FULL_SUITE=1` only for its RSpec subprocess.
Direct RSpec invocations and isolated defect probes can still select individual
examples; they continue to reject pending, skipped, focused, and repeated tests.
Native CLI options fix both assertion and suite-error exit codes at one; RSpec
gives these options precedence over settings declared in spec files.

CODEOWNERS protects this listener and its regression fixtures. Ordinary specs
remain unowned. This detects suite filtering; it is not a sandbox for malicious
Ruby that deliberately replaces the test framework itself.
