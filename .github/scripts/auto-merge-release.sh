#!/usr/bin/env bash
set -euo pipefail

# GitHub enforces the same required checks for every release, including major bumps.
current_version="$(jq -er '.["."]' .release-please-manifest.json)"
component="$(jq -er '.packages["."].component' release-please-config.json)"
gh pr list --base main --state open --label 'autorelease: pending' --json number --jq '.[].number' |
  while read -r number; do
    metadata="$(gh pr view "$number" --json author,baseRefName,headRefName,headRefOid,isCrossRepository,isDraft,title)"
    if ! jq -e --arg current "$current_version" --arg component "$component" -f .github/scripts/release-pr-eligible.jq <<< "$metadata" >/dev/null; then
      echo "Leaving PR #${number} for a maintainer."
      continue
    fi
    head="$(jq -er '.headRefOid' <<< "$metadata")"
    # Required main-branch checks are configured in repository settings.
    # No --admin: GitHub enforces checks, reviews, and any future merge queue.
    gh pr merge "$number" --auto --squash --match-head-commit "$head"
  done
