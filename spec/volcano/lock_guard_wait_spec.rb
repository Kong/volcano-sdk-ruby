# frozen_string_literal: true

require 'bigdecimal'

module Volcano
  RSpec.describe LockGuard do
    subject(:guard) { described_class.new(lease, ttl: 30, started_at: LockLeaseClock.capture) }

    let(:lease) { LockLease.new(key: 'build', token: 'owner', expires_at: nil, fencing_token: 1) }

    before do
      allow(LockLeaseClock).to receive_messages(now: 100.0, suspend_aware?: true)
    end

    [0, -1].each do |timeout|
      it "returns without declaring a valid lease lost when the wait timeout is #{timeout}" do
        expect(guard.wait_lost(timeout: timeout)).to be(false)
        expect(guard).not_to be_lost
        expect(guard.lease).to equal(lease)
      end
    end

    it 'accepts a finite BigDecimal timeout' do
      allow(LockLeaseClock).to receive(:now).and_call_original
      expect(guard.wait_lost(timeout: BigDecimal('0.01'))).to be(false)
      expect(guard).not_to be_lost
    end

    ['later', Complex(1, 1), Float::NAN, Float::INFINITY].each do |timeout|
      it "rejects an invalid timeout #{timeout.inspect}" do
        expect { guard.wait_lost(timeout: timeout) }.to raise_error(ArgumentError, 'invalid timeout')
      end
    end

    it 'finishes an expiry watcher whose lease expired before it could run' do
      instance = guard
      allow(LockLeaseClock).to receive(:now).and_return(131.0)
      watcher = instance.start_expiry_watch

      expect(watcher.join(1)).to equal(watcher)
      expect(instance).to be_lost
      expect(instance.failure).to be_a(Timeout::Error)
      expect(instance.failure.message).to eq(described_class::EXPIRY_MESSAGE)
    ensure
      watcher&.kill&.join
      instance&.stop_expiry_watch
    end

    def observe_waits(waiting)
      condition = ConditionVariable.new
      allow(ConditionVariable).to receive(:new).and_return(condition)
      allow(condition).to receive(:wait).and_wrap_original do |wait, *arguments|
        waiting << true
        wait.call(*arguments)
      end
    end

    it 'wakes a caller waiting without a timeout when ownership is lost' do
      waiting = Queue.new
      observe_waits(waiting)
      instance = guard
      waiter = Thread.new { instance.wait_lost }
      Timeout.timeout(1) { waiting.pop }
      failure = RuntimeError.new('ownership lost')
      instance.mark_lost(failure)

      expect(waiter.join(1)).to equal(waiter)
      expect(waiter.value).to be(true)
      expect(instance.failure).to equal(failure)
    ensure
      waiter&.kill&.join
    end
  end
end
