# frozen_string_literal: true

RSpec.describe Volcano::Client do
  let(:authentication) { instance_double(Volcano.const_get(:Generated)::AuthenticationApi) }
  let(:apis) { instance_double(Volcano.const_get(:GeneratedTransport)::GeneratedApis, authentication: authentication) }
  let(:transport) do
    Volcano.const_get(:GeneratedTransport).new(api_url: 'https://api.test', api_factory: ->(_token) { apis })
  end
  let(:client) { described_class.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  invalid_payloads = [nil, '{'].freeze
  {
    update_user: { password: 'new-password' },
    convert_anonymous: { email: 'user@example.com', password: 'new-password' },
    confirm_email_change: { token: 'confirmation' }
  }.each do |operation, arguments|
    invalid_payloads.each do |payload|
      it "rejects #{payload.inspect} JSON from #{operation} without replacing the session" do
        allow(authentication).to receive("auth_#{operation}_with_http_info").and_return([payload, 200, {}])
        original = client.current_session

        expect { client.auth.public_send(operation, **arguments) }
          .to raise_error(Volcano::Error::AuthenticationError, 'Expected a complete user profile')
        expect(client.current_session).to be(original)
      end
    end
  end
end
