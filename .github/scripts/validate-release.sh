#!/usr/bin/env bash
set -euo pipefail
tag="${RELEASE_TAG:?Release tag is required}"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "Invalid stable release tag"; exit 1; }
git merge-base --is-ancestor HEAD origin/main
test "$(git rev-parse HEAD)" = "$(git rev-parse "refs/tags/$tag^{commit}")"
version="$(jq -er '.["."]' .release-please-manifest.json)"
test "$tag" = "v$version"
# Do not publish an arbitrary tag without a corresponding stable GitHub release.
gh release view "$tag" --json isDraft,isPrerelease --jq 'select(.isDraft == false and .isPrerelease == false)' | jq -e . >/dev/null
