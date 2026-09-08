# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::QueryBuilder do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:query) { client.database('db').from('items').select('id').eq('id', 1).limit(2) }
  let(:replacement) do
    Volcano::Session.new(access_token: 'replacement', refresh_token: 'replacement-refresh', user_id: 'other')
  end

  before do
    client.auth.current_session = Volcano::Session.new(
      access_token: 'old-access', refresh_token: 'old-refresh', user_id: 'user'
    )
    allow(transport).to receive(:query_database_select).and_return(
      response(401), response(200, 'data' => [{ 'id' => 1 }])
    )
    allow(transport).to receive(:auth_refresh).and_return(refresh_response)
  end

  def response(status, body = { 'error' => 'read expired', 'code' => 'expired' })
    Volcano::Transport::Response.new(status:, body:, headers: {}, data: nil)
  end

  def refresh_response
    response(200, 'access_token' => 'new-access', 'refresh_token' => 'new-refresh', 'user' => { 'id' => 'user' })
  end

  def concurrent_results(started, release)
    readers = Array.new(2) { Thread.new { query.execute } }
    Timeout.timeout(5) do
      2.times { started.pop }
      2.times { release << true }
      readers.map(&:value)
    end
  ensure
    readers&.each { |reader| reader.kill.join }
  end

  it 'shares a successful refresh between concurrent reads of the same session' do
    started = Queue.new
    release = Queue.new
    allow(transport).to receive(:query_database_select) do |authorization:, **|
      if authorization == 'old-access'
        started << true
        release.pop
        response(401)
      else
        response(200, 'data' => [{ 'id' => 1 }])
      end
    end
    expect(concurrent_results(started, release)).to eq([[{ 'id' => 1 }], [{ 'id' => 1 }]])
    expect(transport).to have_received(:auth_refresh).once
  end

  it 'refreshes once and replays the same select under the refreshed token' do
    expect(query.execute).to eq([{ 'id' => 1 }])
    expect(transport).to have_received(:auth_refresh).with(authorization: 'anon', refresh_token: 'old-refresh').once
    %w[old-access new-access].each do |token|
      expect(transport).to have_received(:query_database_select).with(
        authorization: token, database_name: 'db',
        body: { 'table' => 'items', 'select' => ['id'],
                'filters' => [{ 'column' => 'id', 'operator' => 'eq', 'value' => 1 }], 'limit' => 2 }
      ).once
    end
  end

  it 'returns the second 401 without refreshing again' do
    allow(transport).to receive(:query_database_select).and_return(response(401))
    expect { query.execute }.to raise_error(Volcano::Error::AuthenticationError, 'read expired')
    expect(transport).to have_received(:query_database_select).twice
    expect(transport).to have_received(:auth_refresh).once
  end

  [401, 503].each do |status|
    it "preserves the read error when refresh returns #{status}" do
      allow(transport).to receive(:auth_refresh).and_return(response(status, 'error' => 'refresh failed'))
      expect { query.execute }.to raise_error(Volcano::Error::AuthenticationError, 'read expired')
      expect(transport).to have_received(:query_database_select).once
      expect(client.current_session.nil?).to eq(status == 401)
    end
  end

  it 'does not refresh a replacement session after a delayed 401' do
    allow(transport).to receive(:query_database_select) do
      client.auth.current_session = replacement
      response(401)
    end
    expect { query.execute }.to raise_error(Volcano::Error::SessionChangedError)
    expect(transport).not_to have_received(:auth_refresh)
    expect(client.current_session).to eq(replacement)
  end

  it 'does not replay after the session is replaced during refresh' do
    allow(transport).to receive(:auth_refresh) do
      client.auth.current_session = replacement
      refresh_response
    end
    expect { query.execute }.to raise_error(Volcano::Error::SessionChangedError)
    expect(transport).to have_received(:query_database_select).once
    expect(client.current_session).to eq(replacement)
  end

  it 'checks session ownership after refresh listeners run' do
    client.auth.on_auth_state_change do |event, _session|
      client.auth.current_session = replacement if event == :token_refreshed
    end
    expect { query.execute }.to raise_error(Volcano::Error::SessionChangedError)
    expect(transport).to have_received(:query_database_select).once
    expect(client.current_session).to eq(replacement)
  end

  it 'does not refresh after a 403' do
    allow(transport).to receive(:query_database_select).and_return(response(403))
    expect { query.execute }.to raise_error(Volcano::Error::AuthenticationError)
    expect(transport).not_to have_received(:auth_refresh)
  end

  it 'keeps realtime fixed-token reads outside automatic refresh' do
    bound_query = client.send(:database_with_token, 'db', 'captured-token').from('items')
    expect { bound_query.execute }.to raise_error(Volcano::Error::AuthenticationError)
    expect(transport).not_to have_received(:auth_refresh)
  end

  %i[insert update delete].each do |operation|
    it "does not replay #{operation} on a 401" do
      method = :"query_database_#{operation}"
      allow(transport).to receive(method).and_return(response(401))
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect { mutation.execute }.to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(method).once
      expect(transport).not_to have_received(:auth_refresh)
    end
  end
end
