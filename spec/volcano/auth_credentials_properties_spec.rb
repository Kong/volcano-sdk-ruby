# frozen_string_literal: true

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  def response(body)
    Volcano::Transport::Response.new(status: 200, body: body, headers: {}, data: nil)
  end

  it 'stores independent snapshots of arbitrary complete sign-in credentials' do
    text = PropCheck::Generators.printable_ascii_string(max: 24)
    generator = PropCheck::Generators.tuple(text, text, text)
    check_property(generator) do |access_suffix, refresh_suffix, user_suffix|
      access = "access-#{access_suffix}"
      refresh = "refresh-#{refresh_suffix}"
      user_id = "user-#{user_suffix}"
      payload = { 'access_token' => access, 'refresh_token' => refresh, 'user' => { 'id' => user_id } }
      allow(transport).to receive(:auth_signin).and_return(response(payload))

      session = client.auth.sign_in(email: 'user@example.test', password: 'secret')
      access.replace('changed')
      refresh.replace('changed')
      user_id.replace('changed')

      expect([session.access_token, session.refresh_token, session.user_id])
        .to eq(["access-#{access_suffix}", "refresh-#{refresh_suffix}", "user-#{user_suffix}"])
      expect(client.auth.current_session).to eq(session)
    end
  end

  it 'does not replace a session with any numeric credential returned by sign-in' do
    established = Volcano::Session.new(access_token: 'existing', refresh_token: 'refresh', user_id: 'user')
    client.auth.current_session = established
    check_property(PropCheck::Generators.choose(0..999)) do |number|
      malformed = [
        { 'access_token' => number }, { 'refresh_token' => number }, { 'user' => { 'id' => number } }
      ]
      malformed.each do |invalid|
        payload = { 'access_token' => 'new', 'refresh_token' => 'new-refresh', 'user' => { 'id' => 'new-user' } }
        allow(transport).to receive(:auth_signin).and_return(response(payload.merge(invalid)))

        expect { client.auth.sign_in(email: 'user@example.test', password: 'secret') }
          .to raise_error(ArgumentError, 'Expected a complete Volcano::Session')
        expect(client.auth.current_session).to eq(established)
      end
    end
  end
end
