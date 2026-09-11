# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Logs do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:request) { { 'resource' => { 'type' => 'function' } } }
  let(:replacement) do
    Volcano::Session.new(access_token: 'replacement', refresh_token: 'refresh', user_id: 'other')
  end

  before do
    client.auth.current_session = Volcano::Session.new(
      access_token: 'old-access', refresh_token: 'old-refresh', user_id: 'user'
    )
    allow(transport).to receive(:auth_refresh).and_return(refresh_response)
  end

  def response(status, body = { 'error' => 'logs denied' })
    Volcano::Transport::Response.new(status:, body:, headers: {}, data: nil)
  end

  def refresh_response
    response(200, 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'user' => { 'id' => 'user' })
  end

  { search: :search_project_logs, activity: :get_project_log_activity }.each do |operation, endpoint|
    context "when reading #{operation}" do
      let(:read) { -> { client.logs.public_send(operation, 'project-1', request) } }

      before do
        allow(transport).to receive(endpoint).and_return(
          response(401), response(200, 'data' => [], 'limit' => 100, 'has_more' => false, 'total' => 0)
        )
      end

      it 'refreshes once and replays the same request' do
        expect(read.call.data).to eq([])
        expect(transport).to have_received(:auth_refresh).with(authorization: 'anon', refresh_token: 'old-refresh').once
        %w[old-access new-access].freeze.each do |token|
          expect(transport).to have_received(endpoint).with(
            authorization: token, project_id: 'project-1', request: request
          ).once
        end
      end

      it 'returns the second 401 without another refresh' do
        allow(transport).to receive(endpoint).and_return(response(401))

        expect { read.call }.to raise_error(Volcano::Error::AuthenticationError, 'logs denied')
        expect(transport).to have_received(endpoint).twice
        expect(transport).to have_received(:auth_refresh).once
      end

      it 'snapshots nested values before refresh callbacks' do
        bodies = []
        client.auth.on_auth_state_change do |event, _session|
          request['resource']['type'] = 'frontend' if event == :token_refreshed
        end
        allow(transport).to receive(endpoint) do |request:, **|
          bodies << JSON.parse(JSON.generate(request))
          response(bodies.one? ? 401 : 200, 'data' => [], 'limit' => 100, 'has_more' => false, 'total' => 0)
        end

        read.call

        expect(request['resource']['type']).to eq('frontend')
        expect(bodies.size).to eq(2)
        expect(bodies).to all(eq('resource' => { 'type' => 'function' }))
      end

      it 'preserves the original error if refresh fails' do
        allow(transport).to receive(:auth_refresh).and_return(response(503, 'error' => 'refresh failed'))

        expect { read.call }.to raise_error(Volcano::Error::AuthenticationError, 'logs denied')
        expect(transport).to have_received(endpoint).once
        expect(transport).to have_received(:auth_refresh).once
      end

      it 'never retries under a replacement session' do
        allow(transport).to receive(:auth_refresh) do
          client.auth.current_session = replacement
          refresh_response
        end

        expect { read.call }.to raise_error(Volcano::Error::SessionChangedError)
        expect(client.current_session).to eq(replacement)
        expect(transport).to have_received(endpoint).once
      end

      [403, 503].freeze.each do |status|
        it "does not refresh after HTTP #{status}" do
          allow(transport).to receive(endpoint).and_return(response(status))

          expect { read.call }.to raise_error(Volcano::Error::VolcanoError, 'logs denied')
          expect(transport).to have_received(endpoint).once
          expect(transport).not_to have_received(:auth_refresh)
        end
      end

      it 'does not refresh after a transport failure' do
        allow(transport).to receive(endpoint).and_raise(Timeout::Error)

        expect { read.call }.to raise_error(Volcano::Error::TransportError)
        expect(transport).to have_received(endpoint).once
        expect(transport).not_to have_received(:auth_refresh)
      end
    end
  end
end
