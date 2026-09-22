# frozen_string_literal: true

module Volcano
  RSpec.describe LockRenewer do
    subject(:renewer) do
      config = described_class::Config.new(ttl: 30, delay: delay, shutdown_timeout: 1)
      described_class.new(locks, 'build', guard, config)
    end

    let(:locks) { instance_double(Locks) }
    let(:delay) { ->(_ttl, remaining:) { remaining } }
    let(:guard) do
      lease = LockLease.new(key: 'build', token: 'owner', expires_at: nil, fencing_token: 1)
      LockGuard.new(lease, ttl: 30, started_at: LockLeaseClock.capture)
    end

    before do
      allow(locks).to receive(:renew)
    end

    it 'can stop before a worker was started without attempting renewal' do
      expect { renewer.stop }.not_to raise_error
      expect(locks).not_to have_received(:renew)
    end

    it 'does not renew when ownership is lost while waiting to renew' do
      observed_loss = Queue.new
      failure = RuntimeError.new('ownership lost while waiting')
      allow(guard).to receive(:renewal_delay) do
        guard.mark_lost(failure)
        0
      end
      allow(guard).to receive(:lost?).and_wrap_original do |original|
        original.call.tap { |lost| observed_loss << true if lost }
      end
      renewer.start
      Timeout.timeout(1) { observed_loss.pop }

      expect(locks).not_to have_received(:renew)
      expect(guard.failure).to equal(failure)
    ensure
      renewer.stop
    end

    it 'does not schedule or send a renewal for an already lost lease' do
      failure = RuntimeError.new('ownership lost')
      guard.mark_lost(failure)
      allow(guard).to receive(:lost?).and_call_original
      allow(delay).to receive(:call).and_call_original
      renewer.start
      renewer.stop

      expect(guard).to have_received(:lost?).once
      expect(delay).not_to have_received(:call)
      expect(locks).not_to have_received(:renew)
      expect(guard.failure).to equal(failure)
    ensure
      renewer.stop
    end
  end
end
