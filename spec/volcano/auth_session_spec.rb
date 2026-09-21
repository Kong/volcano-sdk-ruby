# frozen_string_literal: true

RSpec.describe Volcano::AuthSession do
  let(:attributes) do
    { id: 'session', user_id: 'user', provider: 'email', expires_at: Time.utc(2026),
      is_active: true, is_current: true }
  end

  it 'rejects unknown constructor fields' do
    expect { described_class.new(**attributes, unexpected: true) }
      .to raise_error(ArgumentError, 'unknown keywords: unexpected')
  end

  it 'rejects omitted required constructor fields' do
    expect { described_class.new(**attributes.except(:id)) }
      .to raise_error(ArgumentError, 'missing keywords: id')
  end
end
