# frozen_string_literal: true

require 'timeout'

module Volcano
  RSpec.describe SessionOperations do
    subject(:operations) { described_class.new }

    let(:entered) { Queue.new }
    let(:release) { Queue.new }
    let(:waiting) { Queue.new }

    def observe_waits
      condition = ConditionVariable.new
      allow(ConditionVariable).to receive(:new).and_return(condition)
      allow(condition).to receive(:wait).and_wrap_original do |wait, *arguments|
        waiting << true
        wait.call(*arguments)
      end
    end

    def refresh_in_thread(instance, &)
      Thread.new do
        instance.refresh(&)
      rescue Error::AuthenticationError => e
        e
      end
    end

    def join_value(thread)
      expect(thread.join(1)).to equal(thread)
      thread.value
    end

    def blocked_refresh(instance)
      refresh_in_thread(instance) do
        entered << true
        release.pop
        refresh.call
      end
    end

    shared_examples 'a shared refresh outcome' do
      it 'runs the refresh once and delivers the same outcome to both callers' do
        observe_waits
        instance = operations
        owner = blocked_refresh(instance)
        Timeout.timeout(1) { entered.pop }
        follower = refresh_in_thread(instance) { refresh.call }
        Timeout.timeout(1) { waiting.pop }
        release << true

        expect(join_value(owner)).to equal(outcome)
        expect(join_value(follower)).to equal(outcome)
        expect(refresh).to have_received(:call).once
      ensure
        follower&.kill&.join
        owner&.kill&.join
      end
    end

    context 'when an in-flight refresh succeeds' do
      let(:outcome) { Session.new(access_token: 'access', refresh_token: 'refresh') }
      let(:refresh) { -> { outcome } }

      before { allow(refresh).to receive(:call).and_call_original }

      it_behaves_like 'a shared refresh outcome'
    end

    context 'when an in-flight refresh fails' do
      let(:outcome) { Error::AuthenticationError.new('refresh rejected') }
      let(:refresh) { -> { raise outcome } }

      before { allow(refresh).to receive(:call).and_call_original }

      it_behaves_like 'a shared refresh outcome'
    end

    it 'does not wait again after successful sign-out' do
      expect(operations.sign_out { :revoked }).to eq(:revoked)
      expect(Timeout.timeout(1) { operations.wait_for_sign_out }).to be_nil
      expect(operations).to be_closing
    end

    it 'does not replay a completed sign-out failure to later waiters' do
      expect do
        operations.sign_out { raise Error::AuthenticationError, 'revocation rejected' }
      end.to raise_error(Error::AuthenticationError, 'revocation rejected')

      expect(Timeout.timeout(1) { operations.wait_for_sign_out }).to be_nil
      expect(operations).to be_closing
    end
  end
end
