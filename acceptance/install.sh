#!/usr/bin/env bash
set -euo pipefail
artifact="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
# Bundler's path source describes an unpacked gem, never a source checkout.
# This also supports unpublished candidates with an existing release version.
version="$(ruby -rrubygems/package -e 'puts Gem::Package.new(ARGV.fetch(0)).spec.version' "$artifact")"
gem unpack "$artifact" --target unpacked
mv "unpacked/volcano-sdk-$version" installed-sdk
rmdir unpacked
gem specification "$artifact" --ruby > installed-sdk/volcano-sdk.gemspec
