# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/fake_lock_transport'

RSpec.describe Volcano::Locks do
  subject(:locks) { described_class.new(client, transport) }

  let(:client) { Struct.new(:service_token).new('service-key') }
  let(:transport) { SpecSupport::FakeLockTransport.new }

  it 'renews before yielding a lease without a safe remaining window' do
    transport.acquire_expires_at = Time.now.utc - 1
    yielded = false

    locks.with_lock('build', ttl: 30) do |guard|
      yielded = true
      expect(guard.lease.fencing_token).to eq(8)
    end

    expect(yielded).to be(true)
    expect(call_names).to eq(%i[acquire_project_lock renew_project_lock release_project_lock])
  end

  it 'does not yield when the synchronous renewal loses ownership' do
    transport.acquire_expires_at = Time.now.utc - 1
    transport.renew_handler = lambda do |_arguments|
      transport.response(409, 'message' => 'lock ownership lost')
    end

    expect { |block| locks.with_lock('build', ttl: 30, &block) }
      .to raise_error(Volcano::Error::ConflictError, 'lock ownership lost')
    expect(call_names).to eq(%i[acquire_project_lock renew_project_lock release_project_lock])
  end

  it 'does not yield when a renewal response has no safe window' do
    transport.acquire_expires_at = Time.now.utc - 1
    transport.renew_handler = lambda do |_arguments|
      transport.response(200, 'expires_at' => (Time.now.utc - 1).iso8601)
    end

    expect { |block| locks.with_lock('build', ttl: 30, &block) }
      .to raise_error(Timeout::Error, 'lock renewal returned no safe lease window')
    expect(call_names).to eq(%i[acquire_project_lock renew_project_lock release_project_lock])
  end

  it 'renews in the background and releases the latest lease' do
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    renewed = Queue.new
    transport.renew_handler = lambda do |_arguments|
      renewed << true
      transport.response(200, 'expires_at' => (Time.now.utc + 30).iso8601, 'fencing_token' => 8)
    end

    locks.with_lock('build', ttl: 30) do |guard|
      renewed.pop
      expect(guard.lease.fencing_token).to eq(8)
    end

    expect(transport.calls.last).to match([:release_project_lock, hash_including(token: kind_of(String))])
  end

  it 'reports background renewal failure after releasing' do
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    transport.renew_handler = lambda do |_arguments|
      transport.response(500, 'message' => 'renewal failed')
    end

    expect do
      locks.with_lock('build', ttl: 30) { |guard| expect(guard.wait_lost(timeout: 1)).to be(true) }
    end.to raise_error(Volcano::Error::ServerError, 'renewal failed')
    expect(call_names.last).to eq(:release_project_lock)
  end

  it 'preserves block failures and still releases' do
    expect do
      locks.with_lock('build', ttl: 30) { raise 'body failed' }
    end.to raise_error(RuntimeError, 'body failed')
    expect(call_names).to eq(%i[acquire_project_lock release_project_lock])
  end

  it 'returns the block result' do
    result = locks.with_lock('build', ttl: 30) { :completed }

    expect(result).to eq(:completed)
  end

  it 'rejects an invalid ttl before acquiring' do
    expect { locks.with_lock('build', ttl: 4) { nil } }
      .to raise_error(ArgumentError, 'ttl must be an integer between 5 seconds and 90 days')
    expect(transport.calls).to be_empty
  end

  it 'marks a stalled renewal lost when the lease expires' do
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    stub_const('Volcano::LockAutoRenewal::RENEWAL_SAFETY_MARGIN_SECONDS', 0.0)
    stub_const('Volcano::LockAutoRenewal::RENEWAL_REQUEST_BUDGET_SECONDS', 0.0)
    transport.acquire_expires_at = Time.now.utc + 0.2
    entered = Queue.new
    release = Queue.new
    transport.renew_handler = stalled_renewal(entered, release)

    expect do
      locks.with_lock('build', ttl: 30) do |guard|
        entered.pop
        expect(guard.wait_lost(timeout: 1)).to be(true)
        release << true
      end
    end.to raise_error(Timeout::Error, 'lock lease expired before renewal completed')
  ensure
    release << true if release.empty?
  end

  it 'bounds shutdown without failing a completed block when renewal stalls' do
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    stub_const('Volcano::LockAutoRenewal::RENEWER_SHUTDOWN_TIMEOUT_SECONDS', 0.01)
    entered = Queue.new
    release = Queue.new
    transport.renew_handler = stalled_renewal(entered, release)

    result = locks.with_lock('build', ttl: 30) do
      entered.pop
      :completed
    end

    expect(result).to eq(:completed)
    expect(call_names.last).to eq(:release_project_lock)
  ensure
    release << true if release.empty?
  end

  it 'caps expiry by the monotonic ttl when the wall clock is behind' do
    lease = Volcano::LockLease.new(
      key: 'build', token: 'token', expires_at: Time.now.utc + 5, fencing_token: 7
    )
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    allow(Time).to receive(:now).and_return(Time.now - 10)

    guard = Volcano::LockGuard.new(lease, ttl: 5, started_at: started_at)

    expect(guard.__send__(:expiry_delay)).to be_between(0, 5).exclusive
  end

  it 'records expiry before stopping a starved watcher' do
    lease = Volcano::LockLease.new(
      key: 'build', token: 'token', expires_at: Time.now.utc + 30, fencing_token: 7
    )
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 6
    guard = Volcano::LockGuard.new(lease, ttl: 5, started_at: started_at)

    guard.stop_expiry_watch

    expect(guard).to be_lost
    expect(guard.failure).to be_a(Timeout::Error)
  end

  def call_names
    transport.calls.map(&:first)
  end

  def stalled_renewal(entered, release)
    lambda do |_arguments|
      entered << true
      release.pop
      transport.response(200, 'expires_at' => (Time.now.utc + 30).iso8601)
    end
  end
end
