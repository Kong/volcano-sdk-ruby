# Publishing releases

Release Please maintains the version, changelog, and GitHub releases. Publishing
a GitHub release runs CI and builds a gem; it does not publish to RubyGems.

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

The GitHub `rubygems` environment must permit the `main` branch. Keep any existing
reviewer and branch protections. RubyGems accepts the short-lived GitHub OIDC
token only for this repository, workflow, and environment. No RubyGems password
or API key belongs in GitHub secrets. See the
[RubyGems trusted publishing guide](https://guides.rubygems.org/trusted-publishing/).

## Review a package

Run the `Release package` workflow from `main` with the successful release build
run ID and publishing disabled:

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

## Publish the approved version

After reviewing the package and confirming its RubyGems publisher, run the same
workflow with publishing enabled:

```sh
gh workflow run publish.yml --repo Kong/volcano-sdk-ruby --ref main \
  -f run-id=35237976090 -F publish=true
```

This validates the same successful release build and publishes its original gem
bytes from the `rubygems` environment without rebuilding. Only the publishing job
can request an OIDC token. It downloads the built gem without checking out or
executing SDK code. A repeated push of an existing version fails; check RubyGems
before retrying after an uncertain outcome. Publish a new version for corrections.

Verify the version, ownership, and installation on
[the gem page](https://rubygems.org/gems/volcano-sdk). After the first successful
publication, replace the README's temporary Git-source installation with
`gem "volcano-sdk"`.
