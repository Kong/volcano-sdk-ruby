# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/fake_lock_transport'

RSpec.describe Volcano::Locks do
  subject(:locks) { described_class.new(client, transport) }

  let(:client) { Struct.new(:service_token).new('service-key') }
  let(:transport) { SpecSupport::FakeLockTransport.new }

  it 'renews before yielding a lease without a safe remaining window' do
    advance_acquire_past_ttl
    yielded = false

    locks.with_lock('build', ttl: 30) do |guard|
      yielded = true
      expect(guard.lease.fencing_token).to eq(8)
    end

    expect(yielded).to be(true)
    expect(call_names).to eq(%i[acquire_project_lock renew_project_lock release_project_lock])
  end

  it 'does not yield when the synchronous renewal loses ownership' do
    advance_acquire_past_ttl
    transport.renew_handler = lambda do |_arguments|
      transport.response(409, 'message' => 'lock ownership lost')
    end

    expect { |block| locks.with_lock('build', ttl: 30, &block) }
      .to raise_error(Volcano::Error::ConflictError, 'lock ownership lost')
    expect(call_names).to eq(%i[acquire_project_lock renew_project_lock release_project_lock])
  end

  it 'does not yield when a renewal response has no safe window' do
    clock = advance_acquire_past_ttl
    transport.renew_handler = lambda do |_arguments|
      clock.advance(31)
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
    stub_const('Volcano::LockAutoRenewal::MIN_LOCK_TTL_SECONDS', 1)
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    stub_const('Volcano::LockAutoRenewal::RENEWAL_SAFETY_MARGIN_SECONDS', 0.0)
    stub_const('Volcano::LockAutoRenewal::RENEWAL_REQUEST_BUDGET_SECONDS', 0.0)
    transport.acquire_expires_at = Time.now.utc + 0.2
    entered = Queue.new
    release = Queue.new
    transport.renew_handler = stalled_renewal(entered, release)

    expect do
      locks.with_lock('build', ttl: 1) do |guard|
        entered.pop
        expect(guard.wait_lost(timeout: 2)).to be(true)
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

  it 'ignores wall-clock corrections when measuring lease age' do
    lease = Volcano::LockLease.new(
      key: 'build', token: 'token', expires_at: Time.now.utc + 5, fencing_token: 7
    )
    allow(lease_clock_class).to receive(:suspend_aware?).and_return(true)
    guard = Volcano::LockGuard.new(lease, ttl: 5, started_at: lease_timestamp(lease_clock_class.now))
    allow(Time).to receive(:now).and_return(Time.now + 10)

    expect(guard.__send__(:expiry_delay)).to be_between(0, 5).exclusive
  end

  it 'uses the suspend-aware lease clock for expiry' do
    lease = Volcano::LockLease.new(key: 'build', token: 'token', expires_at: nil, fencing_token: 7)
    allow(lease_clock_class).to receive(:now).and_return(6.0)
    guard = Volcano::LockGuard.new(lease, ttl: 5, started_at: lease_timestamp(0.0))

    expect(guard).to be_lost
    expect(guard.failure).to be_a(Timeout::Error)
  end

  it 'uses wall elapsed time when a suspend-aware clock is unavailable' do
    lease = Volcano::LockLease.new(key: 'build', token: 'token', expires_at: nil, fencing_token: 7)
    wall_started_at = Time.now
    allow(lease_clock_class).to receive_messages(suspend_aware?: false, now: 0.0)
    guard = Volcano::LockGuard.new(
      lease, ttl: 5, started_at: lease_timestamp(0.0, wall: wall_started_at)
    )
    allow(Time).to receive(:now).and_return(wall_started_at + 6)

    expect(guard).to be_lost
  end

  it 'records expiry before stopping a starved watcher' do
    lease = Volcano::LockLease.new(
      key: 'build', token: 'token', expires_at: Time.now.utc + 30, fencing_token: 7
    )
    started_at = lease_timestamp(lease_clock_class.now - 6, wall: Time.now - 6)
    guard = Volcano::LockGuard.new(lease, ttl: 5, started_at: started_at)

    guard.stop_expiry_watch

    expect(guard).to be_lost
    expect(guard.failure).to be_a(Timeout::Error)
  end

  it 'observes expiry synchronously when the watcher has not run' do
    lease = Volcano::LockLease.new(key: 'build', token: 'token', expires_at: nil, fencing_token: 7)
    guard = Volcano::LockGuard.new(
      lease, ttl: 5,
             started_at: lease_timestamp(lease_clock_class.now - 6, wall: Time.now - 6)
    )

    expect(guard).to be_lost
    expect(guard.wait_lost(timeout: 0)).to be(true)
  end

  it 'preserves the absolute acquisition deadline across renewals' do
    lease = Volcano::LockLease.new(key: 'build', token: 'token', expires_at: nil, fencing_token: 7)
    allow(lease_clock_class).to receive(:now).and_return(0.0)
    allow(lease_clock_class).to receive(:suspend_aware?).and_return(true)
    guard = Volcano::LockGuard.new(
      lease, ttl: 7_776_000, started_at: lease_timestamp(0.0, wall: Time.at(0))
    )

    guard.replace_lease(
      lease, started_at: lease_timestamp(7_775_999.0, wall: Time.at(7_775_999))
    )
    allow(lease_clock_class).to receive(:now).and_return(7_775_999.0)

    expect(guard.__send__(:expiry_delay)).to eq(1.0)
  end

  it 'does not synthesize expiry while a completed block waits for release' do
    clock = SpecSupport::FakeLeaseClock.new
    stub_lease_clock(clock)
    transport.release_handler = lambda do |_arguments|
      clock.advance(31)
      transport.response(204, nil)
    end

    result = locks.with_lock('build', ttl: 30) { :completed }

    expect(result).to eq(:completed)
  end

  it 'reports lease loss across a nonlocal block return' do
    stub_const('Volcano::LockAutoRenewal::MAX_RENEWAL_DELAY_SECONDS', 0.01)
    transport.renew_handler = lambda do |_arguments|
      transport.response(500, 'message' => 'renewal failed')
    end

    expect { return_after_loss(locks) }
      .to raise_error(Volcano::Error::ServerError, 'renewal failed')
  end

  it 'retains the acquired key when the caller mutates its string' do
    key = +'build'
    acquired_key = nil

    locks.with_lock(key, ttl: 30) do |guard|
      key.replace('other')
      acquired_key = guard.lease.key
    end

    expect(acquired_key).to eq('build')
    expect(transport.calls.last).to match([:release_project_lock, hash_including(key: 'build')])
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

  def advance_acquire_past_ttl
    clock = SpecSupport::FakeLeaseClock.new
    stub_lease_clock(clock)
    advance_after_acquire(clock)
    clock
  end

  def stub_lease_clock(clock)
    allow(lease_clock_class).to receive(:now) { clock.monotonic }
  end

  def lease_clock_class = Volcano.const_get(:LockLeaseClock)

  def lease_timestamp(monotonic, wall: Time.now)
    lease_clock_class.const_get(:Timestamp).new(monotonic: monotonic, wall: wall)
  end

  def advance_after_acquire(clock)
    allow(transport).to receive(:acquire_project_lock).and_wrap_original do |method, **arguments|
      response = method.call(**arguments)
      clock.advance(31)
      response
    end
  end

  def return_after_loss(locks)
    locks.with_lock('build', ttl: 30) do |guard|
      guard.wait_lost(timeout: 1)
      return :completed
    end
  end
end
