#!/usr/bin/env bash
set -euo pipefail

# An absolute require cannot fall back to Bundler's source-checkout load path.
bundle exec ruby -e 'require File.expand_path("lib/volcano.rb", ARGV.fetch(0)); abort unless Volcano::Client' "${1:?Unpacked gem directory is required}"
