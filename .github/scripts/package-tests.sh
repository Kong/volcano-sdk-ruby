#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
gem unpack "${1:?Built gem is required}" --target "$test_dir"
version="$(ruby -Ilib -rvolcano/version -e 'puts Volcano::VERSION')"
package_dir="$test_dir/volcano-sdk-$version"
bash .github/scripts/smoke-test-gem.sh "$package_dir"

mv "$package_dir/lib/volcano.rb" "$package_dir/lib/volcano.rb.missing"
if bash .github/scripts/smoke-test-gem.sh "$package_dir" >"$test_dir/missing-entrypoint.log" 2>&1; then
  echo "Package smoke test accepted a gem without its entry point." >&2
  exit 1
fi
echo "Package smoke tests passed, including the missing-entrypoint regression."
