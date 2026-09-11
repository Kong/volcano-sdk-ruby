# frozen_string_literal: true

require 'spec_helper'
require_relative '../../features/support/contract_world'
require_relative '../../features/support/broadcast_pause'

RSpec.describe VolcanoContract::BroadcastPause do
  def build_world(leak:)
    channel = instance_double(Volcano::Realtime::Channel, subscribe: nil, unsubscribe: nil)
    handler = nil
    allow(channel).to receive(:on) { |_event, &block| handler = block }
    allow(channel).to receive(:send) do |**message|
      handler.call(message.transform_keys(&:to_s)) if leak || !message.fetch(:value).end_with?('-paused')
    end
    instance_double(
      VolcanoContract::World,
      subscriber: channel,
      publisher: channel,
      realtime_message: { 'event' => 'message', 'value' => 'contract' }
    )
  end

  it 'accepts silence and resumes through the original handler' do
    world = build_world(leak: false)
    result = Async { |task| described_class.new(world).run(task) }.wait

    expect(result).to eq(world.realtime_message)
    expect(world.subscriber).to have_received(:on).once
    expect(world.subscriber).to have_received(:unsubscribe).once
  end

  it 'rejects a publication delivered while paused' do
    world = build_world(leak: true)

    Async do |task|
      expect { described_class.new(world).run(task) }
        .to raise_error(RuntimeError, 'subscriber delivered a message while paused')
    end.wait
  end
end
