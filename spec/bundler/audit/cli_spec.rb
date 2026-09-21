# frozen_string_literal: true

require 'bundler/audit/cli'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe Bundler::Audit::CLI do
  def audit_fixture(version)
    Dir.mktmpdir('volcano-audit-fixture-') do |directory|
      database = File.join(directory, 'advisories')
      write_advisory(database)
      write_lock(directory, version) if version
      Open3.capture3(
        Gem.ruby, Gem.bin_path('bundler-audit', 'bundle-audit'),
        'check', directory, '--database', database, chdir: directory
      )
    end
  end

  def write_advisory(database)
    path = File.join(database, 'gems', 'volcano-audit-fixture')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'CVE-2099-00001.yml'), <<~YAML)
      ---
      gem: volcano-audit-fixture
      cve: 2099-00001
      date: 2099-01-01
      url: https://example.com/advisory
      title: Deliberately injected audit fixture
      description: This package exists only in the temporary lock fixture.
      patched_versions:
        - '>= 2.0.0'
    YAML
  end

  def write_lock(directory, version)
    File.write(File.join(directory, 'Gemfile.lock'), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          volcano-audit-fixture (#{version})

      PLATFORMS
        ruby

      DEPENDENCIES
        volcano-audit-fixture
    LOCK
  end

  it 'accepts a patched dependency' do
    output, errors, status = audit_fixture('2.0.0')

    expect(status.success?).to be(true), output + errors
    expect(output).to include('No vulnerabilities found')
  end

  it 'rejects an advisory affecting a locked dependency' do
    output, errors, status = audit_fixture('1.0.0')

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('CVE-2099-00001', 'Vulnerabilities found!')
  end

  it 'rejects a missing lockfile' do
    output, errors, status = audit_fixture(nil)

    expect(status.exitstatus).to eq(1), output + errors
    expect(output).to include('Gemfile.lock')
  end
end
