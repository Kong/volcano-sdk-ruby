# frozen_string_literal: true

RSpec.describe Volcano::Session do
  it 'rejects a decoder that returns a non-object user snapshot' do
    allow(Volcano.const_get(:SESSION_USER_CODER)).to receive(:load).and_return([])

    expect { described_class.new(access_token: 'token', user: {}) }
      .to raise_error(TypeError, 'Session user snapshot must be a Hash')
  end
end
