#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Pin queue validation from https://github.com/rhysd/actionlint/pull/654 until released.
source_dir="$(go mod download -json github.com/vvoland/actionlint@644076a59742c2d1540ebd4686eab3c308f0e562 | jq -er .Dir)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
# Build in the downloaded module because the fork retains the upstream module path.
go -C "$source_dir" build -mod=readonly -o "$build_dir/actionlint" ./cmd/actionlint
"$build_dir/actionlint" "$@"
