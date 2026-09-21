# Injected defects

`bundle exec rake quality` runs `bin/check-defects`. This small catalog complements
property tests; it does not provide the breadth of a general mutation engine.

The catalog covers service-credential leakage, stale refresh overwrites, incorrect
lock ownership, binary corruption, and premature realtime cursor advancement.
Each case runs its named regression test on the original source, changes exactly
one source occurrence in a temporary checkout, validates Ruby syntax, and reruns
the test. The original checkout is never modified. Snapshots include current
tracked and untracked source, omit ignored dependencies, and reuse locked gems.

Success requires exactly one passing baseline example followed by exactly one
assertion failure for the mutated code. Surviving defects, stale or ambiguous
patches, invalid Ruby, missing or inconsistent reports, empty discovery, pending
examples, runtime crashes, and timeouts all fail. Each child process has a
60-second deadline; the harness kills its process group and reaps it on timeout.

Reports and logs are written under `reports/defects/` and uploaded on CI failure.
Timeouts, invalid mutations, harness failures, and detected defects have distinct
outcomes. The binary property uses seed `12345` for reproducibility. A removed or
renamed regression test fails selection instead of reducing the catalog.

When a refactor changes a mutation target, update its exact before/after strings
and keep the same behavioral defect. Changes to this catalog or harness are
quality-policy changes.
