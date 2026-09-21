#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 2 ]; then echo 'usage: test-acceptance.sh package-file sdk-acceptance.tar.gz' >&2; exit 1; fi
artifact="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
bundle="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xzf "$bundle" -C "$work"
cd "$work"
cp "$artifact" package.gem
ruby -rjson -rdigest -e 'a=JSON.parse(File.read("acceptance.json"));abort "Package differs from acceptance bundle" unless Digest::SHA256.file("package.gem").hexdigest==a.fetch("sha256")'
bash scripts/install.sh package.gem
export BUNDLE_GEMFILE="$work/Gemfile" BUNDLE_PATH="$work/vendor/bundle" BUNDLE_FROZEN=true BUNDLE_DEPLOYMENT=false BUNDLE_FORCE_RUBY_PLATFORM=true
bundle install
bundle exec ruby -rvolcano -e 'abort "SDK source shadowing" unless File.realpath(Gem.loaded_specs.fetch("volcano-sdk").full_gem_path)==File.realpath("installed-sdk")'
bash .github/scripts/smoke-gem.sh package.gem
