# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Auth do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:roles) { ['editor'] }
  let(:metadata) { { 'roles' => roles } }

  def profile = { 'id' => 'user', 'email' => 'updated@example.com', 'status' => 'active' }
  def success = response(200, 'user' => profile)
  def rejected = response(401, 'error' => 'profile denied')

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def capture_requests(transport, transport_method)
    requests = []
    allow(transport).to receive(transport_method) do |**request|
      requests << Marshal.load(Marshal.dump(request))
      requests.length == 1 ? rejected : success
    end
    requests
  end

  before do
    client.auth.current_session = Volcano::Session.new('old-access', 'old-refresh', 'user')
    allow(transport).to receive(:auth_refresh).and_return(
      response(200, 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'user' => profile)
    )
  end

  refresh_statuses = [200, 401, 503]
  non_refresh_statuses = [403, 500]
  replacement_stages = %i[first refresh retry]
  {
    user: :auth_get_user,
    update_user: :auth_update_user,
    convert_anonymous: :auth_convert_anonymous,
    confirm_email_change: :auth_confirm_email_change
  }.each do |operation, transport_method|
    context "when #{operation}" do
      let(:arguments) do
        {
          user: {}, update_user: { password: +'secret', metadata: metadata },
          convert_anonymous: { email: +'updated@example.com', password: +'secret', metadata: metadata },
          confirm_email_change: { token: +'confirmation' }
        }.fetch(operation)
      end

      it 'refreshes once, replays owned arguments, and caches the profile with new credentials' do
        requests = capture_requests(transport, transport_method)
        events = []
        client.auth.on_auth_state_change { |event, _session| events << event }
        allow(transport).to receive(:auth_refresh) do
          roles << 'changed while refreshing'
          arguments.each_value { |value| value.replace('changed') if value.is_a?(String) }
          response(200, 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'user' => profile)
        end

        user = client.auth.public_send(operation, **arguments)
        expect(user.email).to eq(profile.fetch('email'))
        expect(requests.map { |request| request.fetch(:authorization) }).to eq(%w[old-access new-access])
        expect(requests.first.except(:authorization)).to eq(requests.last.except(:authorization))
        expect(client.current_session.to_h.slice(:access_token, :user)).to eq(access_token: 'new-access', user: profile)
        expect(events).to eq(%i[initial_session token_refreshed])
      end

      refresh_statuses.each do |refresh_status|
        it "bounds retries and preserves the original failure when refresh returns #{refresh_status}" do
          allow(transport).to receive(transport_method).and_return(rejected)
          unless refresh_status == 200
            allow(transport).to receive(:auth_refresh).and_return(response(refresh_status,
                                                                           'error' => 'refresh failed'))
          end

          expect { client.auth.public_send(operation, **arguments) }
            .to raise_error(Volcano::Error::AuthenticationError, /profile denied/)
          expect(transport).to have_received(:auth_refresh).once
          expect(transport).to have_received(transport_method).exactly(refresh_status == 200 ? 2 : 1).times
          expect(client.current_session.nil?).to eq(refresh_status == 401)
        end
      end

      non_refresh_statuses.each do |status|
        it "does not retry a #{status}" do
          allow(transport).to receive(transport_method).and_return(response(status, 'error' => 'denied'))
          expect { client.auth.public_send(operation, **arguments) }.to raise_error(Volcano::Error::VolcanoError)
          expect(transport).to have_received(transport_method).once
          expect(transport).not_to have_received(:auth_refresh)
        end
      end

      it 'does not replay an ambiguous transport failure' do
        allow(transport).to receive(transport_method).and_raise(Volcano::Error::TransportError, 'response lost')
        expect { client.auth.public_send(operation, **arguments) }.to raise_error(Volcano::Error::TransportError)
        expect(transport).to have_received(transport_method).once
        expect(transport).not_to have_received(:auth_refresh)
      end

      replacement_stages.each do |replace_at|
        it "preserves a session replaced during #{replace_at}" do
          replacement = Volcano::Session.new('replacement', 'replacement-refresh', 'user')
          requests = 0
          allow(transport).to receive(transport_method) do
            requests += 1
            stage = requests == 1 ? :first : :retry
            client.auth.current_session = replacement if stage == replace_at
            requests == 1 ? rejected : success
          end
          allow(transport).to receive(:auth_refresh) do
            client.auth.current_session = replacement if replace_at == :refresh
            response(200, 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'user' => profile)
          end

          expect { client.auth.public_send(operation, **arguments) }.to raise_error(Volcano::Error::SessionChangedError)
          expect(client.current_session).to eq(replacement)
          expect(requests).to eq(replace_at == :retry ? 2 : 1)
        end
      end
    end
  end
end
