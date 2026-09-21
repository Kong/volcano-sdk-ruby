#!/usr/bin/env bash
set -euo pipefail
artifact="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
# Bundler's path source describes an unpacked gem, never a source checkout.
# This also supports unpublished candidates with an existing release version.
gem unpack "$artifact" --target unpacked
mv unpacked/* installed-sdk
rmdir unpacked
gem specification "$artifact" --ruby > installed-sdk/volcano-sdk.gemspec
