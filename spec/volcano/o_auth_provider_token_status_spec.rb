# frozen_string_literal: true

RSpec.describe Volcano::OAuthProviderTokenStatus do
  %i[message provider].product([nil, '', ' ', 123]).each do |field, value|
    it "rejects #{field} with value #{value.inspect}" do
      attributes = { message: 'refreshed', provider: 'github', expires_in: 3600, field => value }

      expect { described_class.new(**attributes) }
        .to raise_error(TypeError, 'Expected complete OAuth provider token status')
    end
  end

  it 'rejects a non-integer token lifetime' do
    expect { described_class.new(message: 'refreshed', provider: 'github', expires_in: '3600') }
      .to raise_error(TypeError, 'Expected complete OAuth provider token status')
  end
end
