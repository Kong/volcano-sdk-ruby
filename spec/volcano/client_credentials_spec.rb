# frozen_string_literal: true

module Volcano
  RSpec.describe Client do
    let(:transport) { instance_spy(GeneratedTransport) }
    let(:lease) { LockLease.new(key: 'build', token: 'owner', expires_at: nil, fencing_token: 1) }
    let(:client) do
      described_class.new(anon_key: 'anon-key', access_token: access_token, _transport: transport)
    end

    [nil, 'user-access-token'].each do |token|
      context "when no service key is configured and the access token is #{token.inspect}" do
        let(:access_token) { token }

        {
          get_project_lock: ->(locks, _lease) { locks.get('build') },
          acquire_project_lock: ->(locks, _lease) { locks.acquire('build', ttl: 30) },
          renew_project_lock: ->(locks, lease) { locks.renew('build', lease, ttl: 30) },
          release_project_lock: ->(locks, lease) { locks.release('build', lease) },
          force_release_project_lock: ->(locks, _lease) { locks.force_release('build') }
        }.each do |operation, call|
          it "rejects #{operation} before sending other credentials to the transport" do
            expect { call.call(client.locks, lease) }
              .to raise_error(Error::AuthenticationError, 'No service key configured')
            expect(transport).not_to have_received(operation)
          end
        end
      end
    end

    it 'rejects unknown client options instead of silently accepting a typo' do
      expect { described_class.new(anon_key: 'anon-key', timeuot: 5, _transport: transport) }
        .to raise_error(ArgumentError, 'unknown keyword: timeuot')
    end
  end
end
