# Contributing to the Ruby SDK

Use a supported Ruby version (CI covers 3.2 and 3.4), Bundler, Node.js 22,
and Java 21. Node and Java support generation and are not gem runtime dependencies.

## Verify a change

```shell
bundle install
npm ci
bundle exec rake quality
```

CI runs the same command. It checks dependencies, regeneration, lint, tests,
coverage, injected defects, contract bindings, and the installed gem.
See [runtime coverage](maintainers/coverage.md) for coverage reports and focused tests.

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
| Shared behavior                           | Update the canonical requirement ID and Gherkin scenario in Hosting, every affected Hosting-owned language binding, native tests, and equivalent public examples. |
| Native behavior                           | Add native regression coverage and document language-specific behavior. Update shared scenarios only if the shared behavior changes.                                           |
| Public examples                           | Update equivalent examples in every affected language and verify their public API calls.                                                                                       |

Explain unaffected languages and intentional language-specific differences;
method presence alone is not evidence of equivalent behavior. Start behavior
fixes with a failing native test. Never edit generated clients by hand.

Use the same branch name across affected repositories and link the companion
PRs. Keep each PR focused and use Conventional Commits. Obtain clean code and
security reviews and passing required checks on the final commit before merge.
Hosting changes also require human approval.

### Roll out shared behavior

Hosting owns the canonical scenarios and all language bindings under
`tests/sdk-contract`. Its Staging Validation builds each SDK's latest `main`,
installs the distribution in a fresh environment, and exercises public behavior.
Do not copy features or acceptance runners into this repository.

Land compatible server support before an SDK version needs it in production.
Then merge the SDK implementation and native tests. Update the Hosting scenarios
and bindings in the coordinated PR, and validate those SDK main revisions in
Staging Validation. Record the Hosting and SDK commits from that run.

A maintainer manually merges the Release Please version PR; the existing release
and trusted-publisher workflows publish automatically. Hosting acceptance is
independent and does not gate SDK publication.

When the wire contract changes, first build Hosting's public bundle with
`scripts/ci/openapi-bundle.sh <output-directory>` and update the affected SDK's
`openapi/openapi.yaml` from that bundle. Then run its generator and freshness
check. The generator reads the vendored snapshot; it does not update that
snapshot from Hosting. Do not use snapshot equality as a server compatibility
gate.

From a Hosting checkout, verify shared tooling before review:

```shell
npm ci --prefix tests/sdk-contract --ignore-scripts
npm test --prefix tests/sdk-contract
go test ./scripts/ci
```

Use the installed-package runner's `inspect` mode to verify bindings without
provisioning. Staging Validation runs the live suite and requires cleanup. Record
actual live results separately from discovery or package checks.

### Documentation and release boundaries

`docs/` is published to the developer documentation site. Put user-facing
examples there and maintainer instructions in this file or beside the code.
Keep equivalent language examples current in the same coordinated change.
Package checks validate artifacts; they do not authorize publication. Treat
registry-installed quickstarts and release approval as separate release work.
