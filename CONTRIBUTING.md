# Contributing to the Ruby SDK

Use a supported Ruby version (CI covers 3.2 and 3.4), Bundler, Node.js 22,
and Java 21. Node and Java support generation and are not gem runtime dependencies.

## Verify a change

```shell
bundle install
npm ci
bin/check-openapi
bundle exec rubocop --parallel
bundle exec rspec
chmod 600 tests/fixtures/sdk-contract-dry-run.json
CUCUMBER_PUBLISH_QUIET=true \
VOLCANO_SDK_CONTRACT_FIXTURE="$PWD/tests/fixtures/sdk-contract-dry-run.json" \
  bundle exec cucumber features --dry-run --strict --format progress
gem build volcano-sdk.gemspec
bash .github/scripts/smoke-gem.sh volcano-sdk-*.gem
```

After updating `openapi/openapi.yaml` from Hosting's public bundle, regenerate
the internal client with `bin/generate-openapi`. The dry run checks active and
staged phrase bindings without creating fixtures or exercising live behavior.
Keep generated code inside `lib/volcano/generated` and the realtime protocol
adapter behind the public facade.

## Coordinate SDK changes

Follow the [Hosting SDK contract workflow](https://github.com/Kong/volcano-hosting/blob/main/.agents/skills/sdk-contract-coordination/SKILL.md).
Hosting owns the wire contract in `api/openapi.yaml` and the behavioral contract
in `tests/sdk-contract`. JavaScript, Python, and Ruby expose that behavior through
handwritten, idiomatic facades; generated transport code stays internal.

Classify the impact in the PR before changing the contract:

| Change                                    | Required updates                                                                                                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Public facade or SDK-facing wire contract | Audit all three SDKs; update each affected facade, native tests, and public language examples. Regenerate internal clients when their wire snapshot changes.                   |
| Shared behavior                           | Update the canonical requirement ID and Gherkin scenario in Hosting, every affected language binding, checked-in feature copies, native tests, and equivalent public examples. |
| Native behavior                           | Add native regression coverage and document language-specific behavior. Update shared scenarios only if the shared behavior changes.                                           |
| Public examples                           | Update equivalent examples in every affected language and verify their public API calls.                                                                                       |

Explain unaffected languages and intentional language-specific differences;
method presence alone is not evidence of equivalent behavior. Start behavior
fixes with a failing native test. Never edit generated clients by hand.

Use the same branch name across affected repositories and link the companion
PRs. Keep each PR focused and use Conventional Commits. Obtain clean code and
security reviews and passing required checks on the final commit before merge.
Hosting changes also require human approval.

### Roll out shared scenarios

Before merging SDK code, prove it remains compatible with the currently deployed
Hosting contract. Staging Gherkin does not keep runtime code dormant, and the
existing release automation can publish a main-derived package. If new server
support is required, first land a backward-compatible Hosting prerequisite or
keep the SDK PR in draft until an explicitly reviewed release/rollout plan is in
place. Do not merge an incompatible implementation merely because its scenario
is staged.

1. Change the canonical scenario in Hosting once. Copy its bytes into each SDK
   and implement its native binding.
2. Stage new scenarios under `features/staged` while Hosting main still uses the
   older contract. Do not activate scenarios ahead of Hosting.
3. Merge the required SDK changes before validating and merging the coordinated
   Hosting PR. Record the Hosting and SDK revisions used by acceptance.
4. After Hosting merges, promote those unchanged files into `features/contract`
   and run the default binding-discovery checks. Do not keep duplicate active
   and staged copies.

Hosting CI checks out each SDK's latest `main` and records the actual tested
SHAs. Do not introduce a checked-in pin manifest or assume a rerun uses the same
SDK revisions. Generate and verify each SDK against its own OpenAPI snapshot;
compatibility with the server is established by integration tests.

When the wire contract changes, first build Hosting's public bundle with
`scripts/ci/openapi-bundle.sh <output-directory>` and update the affected SDK's
`openapi/openapi.yaml` from that bundle. Then run its generator and freshness
check. The generator reads the vendored snapshot; it does not update that
snapshot from Hosting. Do not use snapshot equality as a server compatibility
gate.

From a Hosting checkout, verify shared tooling and copies before review:

```shell
npm ci --prefix tests/sdk-contract --ignore-scripts
npm test --prefix tests/sdk-contract
bash scripts/ci/run-sdk-contract-tests_test.sh
bash scripts/ci/run-sdk-contract-tests.sh --validate-features-only \
  /path/to/volcano-sdk-js /path/to/volcano-sdk-python /path/to/volcano-sdk-ruby
```

Without `--validate-features-only`, the runner creates and deletes fixtures.
Use an approved disposable environment for live runs; staging and production
require explicit authorization. Ordinary Cloud E2E remains post-merge. Do not
infer live acceptance from tooling checks or a nonblocking staging result.

### Documentation and release boundaries

`docs/` is published to the developer documentation site. Put user-facing
examples there and maintainer instructions in this file or beside the code.
Keep equivalent language examples current in the same coordinated change.
Package checks validate artifacts; they do not authorize publication. Treat
registry-installed quickstarts and release approval as separate release work.
