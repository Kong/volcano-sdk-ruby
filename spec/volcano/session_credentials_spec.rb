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

    it 'normalizes every encoded UUID without changing its digits' do
      check_property(PropCheck::Generators.choose(0..((1 << 128) - 1))) do |number|
        hex = number.to_s(16).rjust(32, '0')
        id = "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
        payload = [JSON.generate(session_id: id.upcase)].pack('m0').tr('+/', '-_').delete('=')

        expect(described_class.session_id("header.#{payload}.signature")).to eq(id)
      end
    end

    it 'rejects a profile without a string user identifier' do
      session = Session.new(access_token: 'access')

      expect { described_class.with_user(session, 'id' => 42) }
        .to raise_error(Error::AuthenticationError, 'Profile has no valid user identifier')
    end
  end
end
