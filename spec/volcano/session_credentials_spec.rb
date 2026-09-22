# frozen_string_literal: true

require 'support/session_fixtures'

module Volcano
  RSpec.describe SessionCredentials do
    include SessionFixtures

    it 'allows the initial session when there is no previous identity' do
      session = Session.new(access_token: access_token, user_id: 'user')

      expect(described_class.validate_refresh(nil, session)).to be_nil
    end

    it 'rejects a missing replacement for a session with a known user' do
      current = Session.new(access_token: 'opaque-access', user_id: 'user')

      expect { described_class.validate_refresh(current, nil) }
        .to raise_error(Error::AuthenticationError, 'Refreshed session belongs to a different user')
    end

    it 'rejects a missing replacement for a session with a server identifier' do
      current = Session.new(access_token: access_token)

      expect { described_class.validate_refresh(current, nil) }
        .to raise_error(Error::AuthenticationError, 'Refreshed credentials belong to a different server session')
    end

    [nil, false, 42, [], {}].each do |token|
      it "does not extract a session identifier from a non-string token: #{token.inspect}" do
        expect(described_class.session_id(token)).to be_nil
      end
    end
  end
end
