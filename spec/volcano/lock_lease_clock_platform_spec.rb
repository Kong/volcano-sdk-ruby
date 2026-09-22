# frozen_string_literal: true

require 'timeout'

module Volcano
  RSpec.describe LockLeaseClock do
    def isolated_clock
      namespace = Module.new
      load File.expand_path('../../lib/volcano/lock_lease_clock.rb', __dir__), namespace
      namespace.const_get(:Volcano, false).const_get(:LockLeaseClock, false)
    end

    def verify_in_child(&)
      # Reloading in a child preserves the parent's constants and coverage counters.
      pid = fork(&)
      _, status = Timeout.timeout(5) { Process.wait2(pid) }
      pid = nil
      expect(status).to be_success
    ensure
      terminate_child(pid) if pid
    end

    def terminate_child(pid)
      Process.kill('KILL', pid)
      Process.wait(pid)
    end

    it 'uses the suspend-aware clock when the platform exposes it' do
      verify_in_child do
        stub_const('Process::CLOCK_BOOTTIME', -1)
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(-1).and_return(123.0)
        clock = isolated_clock

        expect(clock).to be_suspend_aware
        expect(clock.now).to eq(123.0)
        expect(clock).not_to equal(described_class)
      end
    end

    it 'uses the monotonic clock when the platform lacks a suspend-aware clock' do
      verify_in_child do
        hide_const('Process::CLOCK_BOOTTIME')
        clock = isolated_clock
        allow(Process).to receive(:clock_gettime).and_call_original

        expect(clock).not_to be_suspend_aware
        expect(clock.now).to be_a(Float)
        expect(Process).to have_received(:clock_gettime).with(Process::CLOCK_MONOTONIC).at_least(:once)
        expect(clock).not_to equal(described_class)
      end
    end
  end
end
