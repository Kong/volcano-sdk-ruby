#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
metadata='{"author":{"login":"app/kong-volcano-app"},"baseRefName":"main","headRefName":"release-please--branches--main--components--sdk","isCrossRepository":false,"isDraft":false,"title":"chore(main): release 1.6.4"}'
eligible() { jq -e --arg current '1.6.3' --arg component sdk -f .github/scripts/release-pr-eligible.jq >/dev/null; }
eligible <<< "$metadata"
jq '.title="chore(main): release 2.0.0"' <<< "$metadata" | eligible
for change in '.author.login="someone"' '.baseRefName="other"' '.headRefName="feature"' '.isCrossRepository=true' '.isDraft=true' '.title="chore(main): release 1.6.3"' '.title="chore(main): release 1.5.9"' '.title="chore(main): release 1.6.4-rc.1"' '.title="not a release"'; do
  if jq "$change" <<< "$metadata" | eligible; then
    echo "Unsafe release PR accepted: $change" >&2
    exit 1
  fi
done
echo "Release PR eligibility tests passed."
