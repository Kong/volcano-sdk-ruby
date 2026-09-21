# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  [nil, false, '', ' '].each do |value|
    it "rejects an invalid OAuth redirect #{value.inspect} before using the transport" do
      expect { client.auth.sign_in_with_oauth('github', redirect_to: value, state: 'state') }
        .to raise_error(ArgumentError, 'OAuth parameters must be non-empty strings')
    end

    it "rejects an invalid OAuth state #{value.inspect} before using the transport" do
      expect { client.auth.sign_in_with_oauth('github', redirect_to: 'https://app.test/callback', state: value) }
        .to raise_error(ArgumentError, 'OAuth parameters must be non-empty strings')
    end

    it "rejects an invalid OAuth code #{value.inspect} before using the transport" do
      expect do
        client.auth.exchange_oauth_code(
          code: value, redirect_to: 'https://app.test/callback', state: 'state', expected_state: 'state'
        )
      end.to raise_error(ArgumentError, 'OAuth parameters must be non-empty strings')
    end
  end

  %w[a é].each do |character|
    it "accepts exactly 255 state characters starting with #{character}" do
      state = character * 255
      allow(transport).to receive(:auth_oauth_authorization_url).with(
        anon_key: 'anon', provider: 'github', redirect_url: 'https://app.test/callback', client_state: state
      ).and_return('https://auth.test/authorize')

      expect(client.auth.sign_in_with_oauth('github', redirect_to: 'https://app.test/callback', state:))
        .to eq('https://auth.test/authorize')
    end

    it "rejects 256 state characters starting with #{character} before using the transport" do
      expect do
        client.auth.sign_in_with_oauth('github', redirect_to: 'https://app.test/callback', state: character * 256)
      end.to raise_error(ArgumentError, 'OAuth state must not exceed 255 characters')
    end
  end

  it 'rejects different callback states with equal byte lengths before exchanging the code' do
    expect do
      client.auth.exchange_oauth_code(
        code: 'code', redirect_to: 'https://app.test/callback', state: 'actual', expected_state: 'forged'
      )
    end.to raise_error(ArgumentError, 'OAuth state mismatch')
  end
end
