# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  [nil, { 'user' => nil }].each do |payload|
    it "rejects a malformed sign-in object #{payload.inspect} before storing it" do
      established = client.auth.current_session
      allow(transport).to receive(:auth_signin).and_return(response(200, payload))

      expect { client.auth.sign_in(email: 'user@example.test', password: 'secret') }
        .to raise_error(TypeError, 'Expected a complete Volcano::Session')
      expect(client.auth.current_session).to be(established)
    end
  end

  it 'rejects a non-object sign-up acknowledgement' do
    established = client.auth.current_session
    allow(transport).to receive(:auth_signup).and_return(response(201, []))

    expect { client.auth.sign_up(email: 'user@example.test', password: 'secret') }
      .to raise_error(TypeError, 'Expected a complete sign-up acknowledgement')
    expect(client.auth.current_session).to be(established)
  end
end
