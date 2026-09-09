# Releasing

## Release flow

A merge to `main` runs Release Please. Following Volcano CLI's changelog policy,
`feat` and `fix` commits create or update a release PR. A docs-, chore-, or
CI-only merge normally waits for a releasable change; this is not one package
release per merged PR. Breaking changes participate in version calculation.

The Volcano GitHub App creates the release PR. The workflow enables GitHub's
normal squash auto-merge only for that App's same-repository, non-draft release
branch and an increasing stable version. Major versions use the same checks.
It does not approve reviews or bypass branch protections.

Required `main` checks: `test (3.2)` and `test (3.4)`.
Keep these required and auto-merge enabled in repository settings. If reviews
or a merge queue are added later, GitHub enforces those too.

Merging the release PR causes Release Please to create a `vMAJOR.MINOR.PATCH`
tag and GitHub release. `publish.yml` then:

1. Confirms the tag belongs to `main`, matches the release manifest, and has a
   published, non-prerelease GitHub release.
2. Runs the full SDK CI workflow at that exact commit.
3. Builds the package, checks its version against the tag, and smoke-tests it.
4. Passes only the build artifact to a separate OIDC publishing job.

Build jobs cannot request publishing credentials. The publish job does not
check out source or run package build hooks. Workflows serialize releases.

## One-time setup

Install `kong-volcano-app` on `Kong/volcano-sdk-ruby`. Set repository variable
`VOLCANO_APP_ID=4307518` and expose `VOLCANO_APP_KEY` as an Actions secret.
The installation needs Contents, Pull requests, and Issues write permissions.
Minted tokens are scoped to this repository and those permissions. Do not use
`GITHUB_TOKEN` for release writes: its events do not trigger downstream CI or
publishing.

Configure the registry trusted publisher with these exact values:

| Setting | Value |
| --- | --- |
| Package | `volcano-sdk` |
| GitHub owner | `Kong` |
| Repository | `volcano-sdk-ruby` |
| Workflow filename | `publish.yml` |
| GitHub environment | `rubygems` |

The environment allows only the `main` branch and `v*` tags. It has no required
human deployment approval. Registry trust must use this environment name.

The registry did not contain `volcano-sdk` when this setup was prepared.
A registry owner must register a **pending trusted publisher** for that name
before the first publication. The release manifest starts at `0.0.0` to mark
the package as unreleased; the first Release Please release is `0.1.0`.
No package name is reserved merely by committing this workflow.

Release Please updates `lib/volcano/version.rb` and the SDK entry in
`Gemfile.lock`, not the internal OpenAPI generator's npm package.

Repository settings and workflow files do not prove registry access. Activation
is verified only after a release run publishes successfully and the package can
be installed from its registry.

## Recovery

Re-run a failed Release Please job to rediscover an existing pending release PR.
For a failed publish, re-run its original `Publish SDK` workflow run. It rebuilds
and rechecks the release event's commit. There is no arbitrary-ref dispatch input.

An already-published immutable version is not overwritten. npm/RubyGems reject
duplicate uploads; confirm the existing registry version before treating that
specific error as an already-completed publish.
Do not delete or move a released tag to repair a package. Fix the source and
release a new version. For npm, do not republish an older missing version with
the `latest` tag after a newer release; use a deliberate registry recovery.

## Verification

```sh
bash .github/scripts/release-tests.sh
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
```

Run the normal native CI checks and package smoke test before merging workflow
changes. No registry credentials are needed for these checks.

## References

- [Volcano CLI release automation](https://github.com/Kong/volcano-cli/blob/main/.github/workflows/release-please.yml)
- [Release Please authentication and event triggering](https://github.com/googleapis/release-please-action#github-credentials)
- [npm trusted publishing](https://docs.npmjs.com/trusted-publishers/)
- [PyPI trusted publishing](https://docs.pypi.org/trusted-publishers/)
- [RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/)
