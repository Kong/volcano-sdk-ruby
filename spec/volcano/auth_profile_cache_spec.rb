# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }
  let(:profile) { { 'id' => 'original', 'email' => 'original@example.com', 'status' => 'active' } }
  let(:replacement) { Volcano::Session.new('replacement', 'replacement-refresh', 'replacement-user') }

  before do
    response = Volcano::Transport::Response.new(status: 200, body: { 'user' => profile }, headers: {}, data: nil)
    allow(transport).to receive_messages(auth_get_user: response, auth_update_user: response)
  end

  %i[user update_user].each do |operation|
    it "does not cache a stale profile when the session changes during #{operation} model construction" do
      allow(Volcano::User).to receive(:new).and_wrap_original do |original, **attributes|
        user = original.call(**attributes)
        client.auth.current_session = replacement
        user
      end

      expect { client.auth.public_send(operation) }.to raise_error(Volcano::Error::SessionChangedError)
      expect(client.current_session).to eq(replacement)
      expect(client.current_session.user_id).to eq('replacement-user')
    end

    it "normalizes an argument error from #{operation} model construction without caching a user" do
      original_session = client.current_session
      cause = ArgumentError.new('invalid profile model')
      allow(Volcano::User).to receive(:new).and_raise(cause)

      expect { client.auth.public_send(operation) }
        .to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile') do |error|
          expect(error.cause).to equal(cause)
        end
      expect(client.current_session).to equal(original_session)
    end
  end
end
