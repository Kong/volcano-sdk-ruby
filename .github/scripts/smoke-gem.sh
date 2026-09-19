#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  echo 'Usage: smoke-gem.sh path/to/volcano-sdk.gem' >&2
  exit 1
fi

gem_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
script_dir="$(cd "$(dirname "$0")" && pwd)"
artifact_digest="$(shasum -a 256 "$gem_path")"
version="$(ruby -rrubygems/package -e 'puts Gem::Package.new(ARGV.fetch(0)).spec.version' "$gem_path")"
install_root="$(mktemp -d)"
install_root="$(cd "$install_root" && pwd -P)"
trap 'rm -rf "$install_root"' EXIT

# Development and bundled gems must not hide undeclared runtime dependencies.
export GEM_HOME="$install_root/gems"
export GEM_PATH="$GEM_HOME"
export GEM_SPEC_CACHE="$install_root/spec-cache"
unset RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_PATH
cd "$install_root"
gem install "$gem_path" --no-document --clear-sources --source https://rubygems.org --install-dir "$GEM_HOME"
ruby -rvolcano -e '
  spec = Gem.loaded_specs.fetch("volcano-sdk")
  abort "Wrong gem version" unless spec.version.to_s == ARGV.fetch(0) && Volcano::VERSION == ARGV.fetch(0)
  abort "Loaded outside isolated install" unless spec.full_gem_path.start_with?(ENV.fetch("GEM_HOME") + "/")
  abort "Client missing" unless Volcano::Client
  client = Volcano::Client.new(anon_key: "example", access_token: "supplied-access")
  session = client.current_session
  abort "Token bootstrap failed" unless session.access_token == "supplied-access" && session.refresh_token.nil? && session.user_id.nil?
  client.auth.sign_out
  abort "Token-only sign-out failed" unless client.current_session.nil?
  puts "Loaded volcano-sdk #{Volcano::VERSION} from the isolated gem install"
' "$version"
env -i PATH="$PATH" HOME="$install_root" GEM_HOME="$GEM_HOME" GEM_PATH="$GEM_PATH" \
  GEM_SPEC_CACHE="$GEM_SPEC_CACHE" ruby "$script_dir/quickstart.rb"
test "$artifact_digest" = "$(shasum -a 256 "$gem_path")"
printf 'Documented quickstart passed (synthetic HTTP): %s\n' "$artifact_digest"
