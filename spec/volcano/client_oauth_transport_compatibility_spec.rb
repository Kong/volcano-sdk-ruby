# frozen_string_literal: true

RSpec.describe Volcano::Client do
  let(:client) { described_class.new(anon_key: 'anon', api_url: 'https://api.test.volcano.dev') }
  let(:requests) { [] }
  let(:wire) { { 'providers' => [provider_payload] } }
  let(:response) do
    Typhoeus::Response.new(code: 200, body: JSON.generate(wire), headers: { 'Content-Type' => 'application/json' })
  end

  def provider_payload
    {
      'provider' => 'future-provider',
      'linked_at' => '2026-08-30T12:00:00Z',
      'updated_at' => '2026-09-01T12:00:00Z'
    }
  end

  before do
    client.auth.current_session = Volcano::Session.new(
      access_token: 'access-token', refresh_token: 'refresh-token', user_id: 'user'
    )
    allow(Typhoeus::Request).to receive(:new).and_wrap_original do |original, *arguments|
      request = original.call(*arguments)
      requests << request
      allow(request).to receive(:run).and_return(response)
      request
    end
  end

  [{}, { 'provider_user_id' => '583231', 'provider_login' => 'octocat' }].each do |identity|
    context "with provider identity fields #{identity.keys.inspect}" do
      let(:wire) { { 'providers' => [provider_payload.merge(identity)] } }

      it 'preserves the public linked-provider result through real generated deserialization' do
        result = client.auth.list_linked_oauth_providers

        expect(result).to contain_exactly(
          Volcano::LinkedOAuthProvider.new(
            provider: 'future-provider', linked_at: Time.iso8601('2026-08-30T12:00:00Z'),
            updated_at: Time.iso8601('2026-09-01T12:00:00Z')
          )
        )
        expect(result).to be_frozen
        expect(requests.size).to eq(1)
        expect(requests.first.url).to eq('https://api.test.volcano.dev/auth/oauth/providers')
        expect(requests.first.options.fetch(:headers)).to include('Authorization' => 'Bearer access-token')
      end
    end
  end

  context 'with an empty provider collection' do
    let(:wire) { { 'providers' => [] } }

    it 'returns an empty frozen list' do
      expect(client.auth.list_linked_oauth_providers).to eq([]).and be_frozen
    end
  end

  context 'with fractional timestamps and explicit offsets' do
    let(:wire) do
      {
        'providers' => [
          provider_payload.merge(
            'linked_at' => '2024-02-29T12:00:00.123456+05:30',
            'updated_at' => '2026-09-01T12:00:00.654321-04:00'
          )
        ]
      }
    end

    it 'preserves the actual instants and fractional seconds as Time values' do
      result = client.auth.list_linked_oauth_providers.first

      expect(result.linked_at).to eq(Time.iso8601('2024-02-29T12:00:00.123456+05:30'))
      expect(result.updated_at).to eq(Time.iso8601('2026-09-01T12:00:00.654321-04:00'))
    end
  end

  %w[linked_at updated_at].each do |field|
    %w[2026-02-30T12:00:00Z 2026-02-29T12:00:00Z 2026-13-01T12:00:00Z
       2026-09-01T12:00:00 2026-09-01].each do |value|
      context "with invalid wire timestamp #{field}: #{value}" do
        let(:wire) { { 'providers' => [provider_payload.merge(field => value)] } }

        it 'rejects impossible dates and timestamps without an explicit offset' do
          expect { client.auth.list_linked_oauth_providers }
            .to raise_error(TypeError, 'Expected complete linked OAuth providers')
        end
      end
    end
  end

  %w[provider linked_at updated_at].each do |field|
    [nil, false, 42, [], {}, '', " \t"].each do |value|
      context "with invalid #{field}: #{value.inspect}" do
        let(:wire) { { 'providers' => [provider_payload.merge(field => value)] } }

        it 'rejects malformed native provider values without replacing the current session' do
          original = client.current_session

          expect { client.auth.list_linked_oauth_providers }
            .to raise_error(TypeError, 'Expected complete linked OAuth providers')
          expect(client.current_session).to be(original)
        end
      end
    end

    context "without #{field}" do
      let(:wire) { { 'providers' => [provider_payload.reject { |key, _value| key == field }] } }

      it 'rejects missing public result fields' do
        expect { client.auth.list_linked_oauth_providers }
          .to raise_error(TypeError, 'Expected complete linked OAuth providers')
      end
    end
  end

  [nil, [], {}, { 'providers' => nil }, { 'providers' => {} }].each do |payload|
    context "with incomplete provider collection #{payload.inspect}" do
      let(:wire) { payload }

      it 'rejects the malformed collection' do
        expect { client.auth.list_linked_oauth_providers }
          .to raise_error(TypeError, 'Expected complete linked OAuth providers')
      end
    end
  end

  [nil, false, 42, [], {}, 'invalid'].each do |provider|
    context "with malformed provider entry #{provider.inspect}" do
      let(:wire) { { 'providers' => [provider] } }

      it 'rejects the malformed entry' do
        expect { client.auth.list_linked_oauth_providers }
          .to raise_error(TypeError, 'Expected complete linked OAuth providers')
      end
    end
  end

  ['', 'not-json'].each do |body|
    context "with invalid JSON response #{body.inspect}" do
      let(:response) { Typhoeus::Response.new(code: 200, body:, headers: { 'Content-Type' => 'application/json' }) }

      it 'rejects the invalid transport body' do
        expect { client.auth.list_linked_oauth_providers }
          .to raise_error(TypeError, 'Expected complete linked OAuth providers')
      end
    end
  end
end
