# frozen_string_literal: true

require 'spec_helper'

module SpecSupport
  BlockingCall = Volcano::Realtime.const_get(:BlockingCall, false)
end

RSpec.describe SpecSupport::BlockingCall do
  it 'returns a value produced outside the caller thread' do
    caller = Thread.current
    worker = nil
    result = described_class.call do
      worker = Thread.current
      42
    end

    expect(result).to eq(42)
    expect(worker).not_to equal(caller)
  end

  it 'returns nil when the operation does' do
    expect(described_class.call { nil }).to be_nil
  end

  it 're-raises the worker error in the caller thread' do
    error = StandardError.new('failed')

    expect { described_class.call { raise error } }.to raise_error(error)
  end
end
