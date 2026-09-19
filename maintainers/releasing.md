# Release evidence and recovery

The checked-in release and publish workflows own versioning and publication.
This checklist does not authorize a release, a registry mutation or an environment approval.

## Before publication

1. Identify the release PR, exact source commit, version, tag and intended registry account. Inspect the generated changelog and package metadata.
2. Require passing native checks: `bin/check-openapi`, `bundle exec rubocop`, `bundle exec rspec`, and the gem build and isolated install checks in CI. Verify the OpenAPI snapshot and generated output using the checked-in commands.
3. Obtain clean code and security reviews. Record the approved shared-acceptance run and exact Hosting/SDK revisions for behavior changes; dry runs and synthetic HTTP tests are not live acceptance.
4. Build the gem locally, install it in a clean environment, and run the exact public quickstart. Retain its digest and inventory as candidate package-content evidence; this is not proof of the bytes the release workflow will later build.
5. Confirm explicit release authorization before any publication action. The existing automatic release path may publish after a release PR lands; a successful check or an unprotected environment is not itself release approval. Resolve authorization before merging a release PR rather than assuming `rubygems` has a human gate.

Use the existing workflows and their tag, ancestry, identity and artifact checks.
The release-triggered workflow builds after the GitHub release is published, then passes its preserved artifact to the registry job without rebuilding. A local candidate and the workflow artifact are separate builds. Authorize the source version and this workflow before triggering that path; do not claim exact-byte pre-publication approval from the local check. If approval of specific bytes is required, first add and review a build/test/approval boundary that holds that same artifact before publication. Do not retag a release or overwrite a published version.
The existing manual recovery path can download a successful release run’s preserved gem and verify a reviewed SHA-256. It does not establish a general pre-publication hold: the automatic release path can already have published that run’s gem.

After publication, verify the registry's package identity and version, digest/provenance where available, clean installation, and the documented quickstart against the approved platform revision.
Record the workflow URL and registry URL. Source-main tests alone do not prove the published artifact contains that source.

The existing `.github/scripts/smoke-gem.sh` check also executes the unchanged
public quickstart from its isolated gem install, without publisher credentials.
It checks sign-in, profile retrieval and logout against synthetic local HTTP
responses and records the unchanged gem's SHA256. PR CI and the automatic
release build run this check before the artifact is uploaded. The manual
recovery path reuses the original artifact; it does not rerun the quickstart.
This does not replace registry installation or approved live platform acceptance.

## Recover from a bad release

For an application regression, first restore its previously tested application revision and dependency lock using [the public guide](../docs/versions.md).
Confirm compatibility with current server configuration and data; an SDK downgrade does not roll either back.

Record the affected versions, symptom, safe previous version, artifact digests and any required data/server remediation in the incident or release issue.
Prepare a reviewed fix as a new version. Do not republish altered bytes under an existing version.
If package deprecation, yanking, an npm tag move or another registry action is needed, preview the exact package/version/action and obtain explicit release-owner authorization first.
Keep already published artifacts and audit evidence available unless the approved response specifically requires otherwise.

Before calling recovery verified, run clean installs and the affected application/quickstart checks for both the safe version and the proposed fix. Record actual results and remaining limits; a written rollback plan is not a performed rollback.
