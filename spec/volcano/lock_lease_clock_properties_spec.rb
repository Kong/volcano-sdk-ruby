# frozen_string_literal: true

module Volcano
  RSpec.describe LockLeaseClock do
    let(:timestamp) { described_class.const_get(:Timestamp) }
    let(:seconds) { PropCheck::Generators.choose(0..900) }

    it 'uses the earlier monotonic or wall deadline when the clock cannot observe suspension' do
      generator = PropCheck::Generators.tuple(PropCheck::Generators.choose(1..600), seconds, seconds)
      check_property(generator) do |ttl, monotonic_elapsed, wall_elapsed|
        started_at = timestamp.new(monotonic: 1_000.0, wall: Time.at(1_000))
        clock = described_class.new(ttl: ttl, started_at: started_at)
        allow(described_class).to receive_messages(now: 1_000.0 + monotonic_elapsed, suspend_aware?: false)
        allow(Time).to receive(:now).and_return(Time.at(1_000 + wall_elapsed))

        expect(clock.remaining).to eq([ttl - monotonic_elapsed, ttl - wall_elapsed].min.clamp(0, ttl))
      end
    end

    it 'never extends a renewed lease beyond its original absolute deadline' do
      check_property(PropCheck::Generators.choose(1..3_600)) do |ttl|
        started_at = timestamp.new(monotonic: 0.0, wall: Time.at(0))
        clock = described_class.new(ttl: ttl, started_at: started_at)
        renewed_at = described_class::MAX_LEASE_LIFETIME_SECONDS - (ttl / 2.0)
        clock.reset(timestamp.new(monotonic: renewed_at, wall: Time.at(renewed_at)))
        allow(described_class).to receive_messages(now: renewed_at, suspend_aware?: true)

        expect(clock.remaining).to eq(ttl / 2.0)
        allow(described_class).to receive(:now).and_return(described_class::MAX_LEASE_LIFETIME_SECONDS + 1.0)
        expect(clock.remaining).to eq(0.0)

        allow(described_class).to receive_messages(now: renewed_at, suspend_aware?: false)
        allow(Time).to receive(:now).and_return(Time.at(described_class::MAX_LEASE_LIFETIME_SECONDS + 1.0))
        expect(clock.remaining).to eq(0.0)
      end
    end
  end
end
