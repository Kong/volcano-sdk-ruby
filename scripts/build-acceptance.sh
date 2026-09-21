#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 2 ]; then echo 'usage: build-acceptance.sh sdk.gem output-directory' >&2; exit 1; fi
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
artifact="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$2"
output="$(cd "$2" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts" "$work/.github/scripts" "$work/spec/support" "$work/docs"

cp "$repo_dir/acceptance/Gemfile" "$work/"
cp -R "$repo_dir/features" "$work/"
cp "$repo_dir/.github/scripts/"{smoke-gem.sh,quickstart.rb} "$work/.github/scripts/"
cp "$repo_dir/spec/support/recording_server.rb" "$work/spec/support/"
cp "$repo_dir/docs/README.md" "$work/docs/"
cd "$work"
export VOLCANO_ACCEPTANCE_VERSION
VOLCANO_ACCEPTANCE_VERSION="$(ruby -rrubygems/package -e 'puts Gem::Package.new(ARGV.fetch(0)).spec.version' "$artifact")"
cp "$repo_dir/acceptance/install.sh" scripts/install.sh
bash scripts/install.sh "$artifact"
export BUNDLE_DEPLOYMENT=false BUNDLE_FROZEN=false
export BUNDLE_GEMFILE="$work/Gemfile" BUNDLE_PATH="$work/vendor/bundle" BUNDLE_FORCE_RUBY_PLATFORM=true
bundle lock --add-checksums
BUNDLE_FROZEN=true bundle install
ruby -rjson -rdigest -e '
  artifact = ARGV.fetch(0)
  File.write("acceptance.json", JSON.pretty_generate({schema: 1, language: "ruby", package: "volcano-sdk", version: ENV.fetch("VOLCANO_ACCEPTANCE_VERSION"), filename: "volcano-sdk-#{ENV.fetch("VOLCANO_ACCEPTANCE_VERSION")}.gem", sha256: Digest::SHA256.file(artifact).hexdigest}))
' "$artifact"
bundle exec ruby -rvolcano -e 'abort "SDK source shadowing" unless File.realpath(Gem.loaded_specs.fetch("volcano-sdk").full_gem_path) == File.realpath("installed-sdk")'
bash .github/scripts/smoke-gem.sh "$artifact"
rm -rf vendor .bundle installed-sdk
tar -czf "$output/sdk-acceptance.tar.gz" .
