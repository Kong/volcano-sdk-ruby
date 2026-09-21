# frozen_string_literal: true

RSpec.describe Volcano::LockState do
  it 'retains an absent expiry for an unheld lock' do
    expect(described_class.new(held: false, expires_at: nil, fencing_token: nil))
      .to have_attributes(held: false, expires_at: nil, fencing_token: nil)
  end

  it 'copies an unfrozen expiry before exposing it' do
    expiry = Time.utc(2026)
    state = described_class.new(held: true, expires_at: expiry, fencing_token: 1)
    expiry.localtime('+02:00')

    expect(state.expires_at).to be_frozen
    expect(state.expires_at.utc?).to be(true)
    expect(state.expires_at).not_to equal(expiry)
  end

  it 'retains an already immutable expiry' do
    expiry = Time.utc(2026).freeze

    expect(described_class.new(held: true, expires_at: expiry, fencing_token: 1).expires_at)
      .to equal(expiry)
  end
end
