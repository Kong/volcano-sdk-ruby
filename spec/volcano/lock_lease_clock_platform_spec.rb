# frozen_string_literal: true

require 'open3'

module Volcano
  RSpec.describe LockLeaseClock do
    def clock_probe(setup)
      source = <<~RUBY
        require 'json'
        require 'rspec/mocks/standalone'
        RSpec::Mocks.configuration.verify_partial_doubles = true
        #{setup}
        require 'volcano/lock_lease_clock'
        clock = Volcano::LockLeaseClock
        puts JSON.generate(suspend_aware: clock.suspend_aware?, now: clock.now)
      RUBY
      output, errors, status = Open3.capture3(Gem.ruby, '-Ilib', '-e', source)
      expect(status).to be_success, errors
      JSON.parse(output)
    end

    it 'uses the suspend-aware clock when the platform exposes it' do
      result = clock_probe(<<~RUBY)
        stub_const('Process::CLOCK_BOOTTIME', -1)
        allow(Process).to receive(:clock_gettime).with(-1).and_return(123.0)
      RUBY

      expect(result).to eq('suspend_aware' => true, 'now' => 123.0)
    end

    it 'uses the monotonic clock when the platform lacks a suspend-aware clock' do
      result = clock_probe(<<~RUBY)
        hide_const('Process::CLOCK_BOOTTIME')
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(456.0)
      RUBY

      expect(result).to eq('suspend_aware' => false, 'now' => 456.0)
    end
  end
end
