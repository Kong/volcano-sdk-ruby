# Publishing releases

Merging a Release Please release PR automatically publishes its version to
RubyGems after the release checks pass. No separate publish action is required.

## Automatic release flow

1. Release Please uses the Kong GitHub App token to create the version tag and
   publish the GitHub release after its PR merges into `main`.
2. The `release: published` event starts `publish.yml`. Only stable, non-draft
   releases authored by `kong-volcano-app[bot]` enter the automatic path.
3. The workflow verifies tag ancestry and the release manifest, runs CI on Ruby
   3.2 and 3.4, and builds and smoke-tests the gem. The gem name and version must
   match the release. It records the file inventory and SHA-256 with the artifact.
4. A separate job downloads that artifact, verifies its checksum, obtains a
   short-lived RubyGems OIDC credential, and pushes the gem from the `rubygems`
   environment. This job never checks out or executes SDK code.
5. A final job adds the RubyGems version link to the GitHub release notes.

Releases queue without cancelling pending versions, matching the JavaScript SDK
release pipeline. RubyGems selects its latest version by version number; there
is no npm-style `latest` tag to move.

Keep the GitHub App token in `release-please.yml`: releases created with the
repository's `GITHUB_TOKEN` do not trigger a new release workflow. See
[GitHub's workflow-trigger rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow).

A failed validation, CI run, build, or package check blocks publication. The
release workflow's result is the publication result; check it before announcing
the version.

## Configure RubyGems once

Sign in to the Kong RubyGems account and verify the profile is `kong`
(`rubygems@konghq.com`). Keep MFA enabled. For the first release, create a
[pending trusted publisher](https://rubygems.org/profile/oidc/pending_trusted_publishers)
with these exact values:

| Field | Value |
| --- | --- |
| Gem name | `volcano-sdk` |
| Repository owner | `Kong` |
| Repository name | `volcano-sdk-ruby` |
| Workflow filename | `publish.yml` |
| Environment | `rubygems` |

Leave the optional workflow repository fields empty; the publishing job runs in
this repository. The first successful push creates the gem and makes the account
that registered the pending publisher its owner. A pending publisher does not
reserve the gem name. RubyGems displays its expiry; recreate it if it expires
before the first push. For an existing gem, verify its owners and add the same
publisher from that gem's Trusted publishers page instead.

The GitHub `rubygems` environment permits `v*` tags for automatic releases and
`main` for manual recovery. Preserve these restrictions and any existing
protections. A required environment reviewer pauses publication for approval;
the current environment has no reviewer gate. RubyGems accepts the short-lived GitHub OIDC
token only for this repository, workflow, and environment. No RubyGems password
or API key belongs in GitHub secrets. See the
[RubyGems trusted publishing guide](https://guides.rubygems.org/trusted-publishing/).

## Inspect a release or recover publication

Normal releases publish automatically. If publication fails, inspect the failed
job and rerun it after addressing the cause. If the push may already have
succeeded, check RubyGems before retrying: a repeated push of an existing version
fails. Publish a new version for corrections.

For a successful package-only run from before automatic publishing was enabled,
the manual path can publish its original artifact without rebuilding. First run
`Release package` from `main` with that release build run ID and publishing
disabled:

```sh
gh workflow run publish.yml --repo Kong/volcano-sdk-ruby --ref main \
  -f run-id=35237976090 -F publish=false
```

Find the run ID in the successful release build's Actions URL. The workflow
accepts only successful `publish.yml` release-event runs from this repository.
It rejects draft releases, prereleases, moved tags, commits outside `main`,
version mismatches, and missing or expired artifacts. The original release run
must have passed CI and the unpacked gem smoke test.

Download the manual run's `publish-package` artifact. Review the gem's name,
version, file inventory (`package-files.txt`), and SHA-256 (`SHA256SUMS`), plus the
source commit in the job summary. Unpack the gem when inspecting its contents:

```sh
sha256sum --check SHA256SUMS
gem unpack volcano-sdk-0.5.2.gem --target unpacked
```

On macOS, use `shasum -a 256 -c SHA256SUMS` to check the checksum.

### Publish an existing package-only build

After reviewing the package and confirming its RubyGems publisher, run the same
workflow with publishing enabled and the reviewed gem checksum. The values below
identify the existing `v0.5.2` build; use the run ID and checksum you reviewed for
other releases:

```sh
gh workflow run publish.yml --repo Kong/volcano-sdk-ruby --ref main \
  -f run-id=35237976090 -F publish=true \
  -f sha256=8a03d6e4d1424644140e4b2f47597ca64e4c771d74a9394e4f36c2faa1a41e7a
```

This validates the same successful release build and publishes its original gem
bytes without rebuilding. A missing or different checksum blocks manual
publication. Verify the version, ownership, and installation on
[the gem page](https://rubygems.org/gems/volcano-sdk).
