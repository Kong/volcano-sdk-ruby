# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'tmpdir'

desc 'Run the same SDK checks locally and in CI'
task quality: %w[quality:audit quality:generated quality:lint quality:spec quality:contract quality:package]

desc 'Audit locked dependencies with current security advisories'
task 'quality:audit' do
  ruby Gem.bin_path('bundler-audit', 'bundle-audit'), 'check', '--update'
end

desc 'Verify the generated OpenAPI client'
task 'quality:generated' do
  sh 'bin/check-openapi'
end

desc 'Lint all maintained Ruby code'
task 'quality:lint' do
  ruby Gem.bin_path('rubocop', 'rubocop'), '--parallel'
end

desc 'Run the unit tests'
task 'quality:spec' do
  ruby Gem.bin_path('rspec-core', 'rspec')
end

desc 'Validate contract feature bindings without provisioning resources'
task 'quality:contract' do
  fixture = File.expand_path('tests/fixtures/sdk-contract-dry-run.json', __dir__)
  File.chmod(0o600, fixture)
  sh({ 'CUCUMBER_PUBLISH_QUIET' => 'true', 'VOLCANO_SDK_CONTRACT_FIXTURE' => fixture },
     Gem.ruby, Gem.bin_path('cucumber', 'cucumber'), 'features/contract',
     '--dry-run', '--strict', '--format', 'progress')
end

desc 'Build and smoke test a fresh gem in an isolated install'
task 'quality:package' do
  Dir.mktmpdir('volcano-sdk-quality-') do |directory|
    artifact = File.join(directory, 'volcano-sdk.gem')
    Bundler.with_unbundled_env do
      sh Gem.ruby, '-S', 'gem', 'build', 'volcano-sdk.gemspec', '--output', artifact
      sh 'bash', '.github/scripts/smoke-gem.sh', artifact
    end
  end
end
