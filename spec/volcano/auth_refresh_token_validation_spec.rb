# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }

  ['header.@@@.signature', 'header.eA.signature'].each do |token|
    it "rejects malformed session claims in #{token} before transport use" do
      client = Volcano::Client.new(
        anon_key: 'anon', access_token: token, refresh_token: 'refresh', _transport: transport
      )
      original = client.current_session

      expect { client.auth.refresh_session }.to raise_error(
        Volcano::Error::AuthenticationError, 'Cannot refresh supplied credentials without a session identifier'
      )
      expect(client.current_session).to be(original)
    end
  end
end
