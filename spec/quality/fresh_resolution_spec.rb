# frozen_string_literal: true

require 'tmpdir'
require_relative '../../maintainers/quality/fresh_resolution'

RSpec.describe FreshResolution do
  let(:directory) { Dir.mktmpdir('volcano-fresh-resolution-') }

  after { FileUtils.remove_entry(directory) }

  it 'reads the locked runtime closure without development gems' do
    File.write(File.join(directory, 'Gemfile.lock'), <<~LOCK)
      PATH
        remote: .
        specs:
          volcano-sdk (1.0.0)
            typhoeus (= 1.6.0)

      GEM
        remote: https://rubygems.org/
        specs:
          ethon (0.18.0)
            ffi (>= 1.15.0)
          ffi (1.17.4)
          ffi (1.17.4-x86_64-linux-gnu)
          rspec (3.13.2)
          typhoeus (1.6.0)
            ethon (>= 0.18.0)

      PLATFORMS
        ruby
        x86_64-linux

      DEPENDENCIES
        rspec (= 3.13.2)
        volcano-sdk!

      BUNDLED WITH
         2.6.9
    LOCK

    expect(described_class.locked(directory)).to eq('typhoeus' => '1.6.0', 'ethon' => '0.18.0', 'ffi' => '1.17.4')
  end

  it 'warns about each gem a fresh install resolves differently and writes the step summary' do
    summary = File.join(directory, 'summary.md')
    locked = { 'ethon' => '0.18.0', 'typhoeus' => '1.6.0' }
    installed = { 'ethon' => ['0.19.0', false], 'openssl' => ['3.3.0', true], 'typhoeus' => ['1.6.0', false] }

    expect { described_class.report(locked, installed, summary) }.to output(
      a_string_starting_with(
        "::warning::ethon: Gemfile.lock 0.18.0, fresh install 0.19.0\n" \
        "::warning::openssl: Gemfile.lock none, fresh install 3.3.0 (Ruby default gem)\n" \
        "| Gem | Gemfile.lock | Fresh install |\n"
      )
    ).to_stdout
    expect(File.read(summary)).to include("| ethon | 0.18.0 | 0.19.0 |\n", "| typhoeus | 1.6.0 | 1.6.0 |\n")
  end
end
