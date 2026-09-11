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

  %i[client auth].each do |entry_point|
    it "preserves the #{entry_point} session_read compatibility entry point" do
      tokens = []
      receiver = entry_point == :client ? client : client.auth
      result = receiver.session_read do |token|
        tokens << token
        response(token == 'old-access' ? 401 : 200)
      end

      expect(result.status).to eq(200)
      expect(tokens).to eq(%w[old-access new-access])
      expect(transport).to have_received(:auth_refresh).once
    end
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

  def read_result
    query.execute
  rescue Volcano::Error::VolcanoError => e
    e
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

  it 'preserves each concurrent read error when refresh clears the session' do
    started = Queue.new
    release = Queue.new
    allow(transport).to receive(:auth_refresh).and_return(response(401, 'error' => 'refresh failed'))
    allow(transport).to receive(:query_database_select) do
      started << true
      release.pop
      response(401)
    end
    readers = Array.new(2) { Thread.new { read_result } }
    2.times { started.pop }
    2.times { release << true }
    expect(readers.map { |reader| reader.value.message }).to eq(['read expired', 'read expired'])
    expect(transport).to have_received(:auth_refresh).once
  ensure
    readers&.each { |reader| reader.kill.join }
  end

  context 'when a refresh listener waits for a coalesced read before replacing the session' do
    let(:coordination) { { started: Queue.new, release: Queue.new, results: Queue.new, completed: [] } }

    before do
      allow(transport).to receive(:query_database_select) do |authorization:, **|
        if authorization == 'old-access'
          coordination[:started] << true
          coordination[:release].pop
          response(401)
        else
          response(200, 'data' => [{ 'id' => 1 }])
        end
      end
      client.auth.on_auth_state_change do |event, _session|
        next unless event == :token_refreshed

        coordination[:release] << true
        coordination[:completed] << Timeout.timeout(5) { coordination[:results].pop }
        client.auth.current_session = replacement
      end
    end

    it 'preserves the completed read and rejects the still-pending owner read' do
      readers = Array.new(2) { Thread.new { read_result.tap { |result| coordination[:results] << result } } }
      outcomes = Timeout.timeout(5) do
        2.times { coordination[:started].pop }
        coordination[:release] << true
        readers.map(&:value)
      end
      expect(coordination[:completed]).to eq([[{ 'id' => 1 }]])
      expect(outcomes).to contain_exactly([{ 'id' => 1 }], an_instance_of(Volcano::Error::SessionChangedError))
      expect(client.auth.current_session).to eq(replacement)
      expect(transport).to have_received(:auth_refresh).once
    ensure
      readers&.each { |reader| reader.kill.join }
    end
  end

  it 'allows a refresh listener to wait for another refresh thread' do
    completed = []
    workers = []
    subscription = client.auth.on_auth_state_change do |event, _session|
      next unless event == :token_refreshed

      subscription.unsubscribe
      worker = Thread.new { client.auth.refresh_session }
      workers << worker
      completed << !worker.join(1).nil?
    end
    query.execute
    workers.each { |worker| worker.join(5) }
    expect(completed).to eq([true])
  ensure
    workers&.each { |worker| worker.kill.join }
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

  it 'preserves the read error when refresh returns an incomplete session' do
    allow(transport).to receive(:auth_refresh).and_return(response(200, {}))
    expect { query.execute }.to raise_error(Volcano::Error::AuthenticationError, 'read expired')
    expect(transport).to have_received(:query_database_select).once
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

  it 'rejects a replacement adopted by the failed-refresh listener' do
    allow(transport).to receive(:auth_refresh).and_return(response(401))
    client.auth.on_auth_state_change do |event, _session|
      client.auth.current_session = replacement if event == :signed_out
    end
    expect { query.execute }.to raise_error(Volcano::Error::SessionChangedError)
    expect(client.current_session).to eq(replacement)
  end

  it 'rejects rows if the session changes during replay' do
    allow(transport).to receive(:query_database_select) do |authorization:, **|
      next response(401) if authorization == 'old-access'

      client.auth.current_session = replacement
      response(200, 'data' => [{ 'id' => 1 }])
    end
    expect { query.execute }.to raise_error(Volcano::Error::SessionChangedError)
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
    it "refreshes once and replays the same #{operation} on a 401" do
      calls = []
      method = :"query_database_#{operation}"
      allow(transport).to receive(method) do |**arguments|
        calls << arguments
        calls.size == 1 ? response(401) : response(200, 'data' => [{ 'id' => 1 }])
      end
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect(mutation.execute).to eq([{ 'id' => 1 }])
      expect(calls.map { |call| call.fetch(:authorization) }).to eq(%w[old-access new-access])
      expect(calls.first.except(:authorization)).to eq(calls.last.except(:authorization))
      expect(transport).to have_received(:auth_refresh).once
    end

    it "does not replay #{operation} on a 403" do
      method = :"query_database_#{operation}"
      allow(transport).to receive(method).and_return(response(403))
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect { mutation.execute }.to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(method).once
      expect(transport).not_to have_received(:auth_refresh)
    end

    it "bounds #{operation} to one retry after repeated 401 responses" do
      method = :"query_database_#{operation}"
      allow(transport).to receive(method).and_return(response(401))
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect { mutation.execute }.to raise_error(Volcano::Error::AuthenticationError)
      expect(transport).to have_received(method).twice
      expect(transport).to have_received(:auth_refresh).once
    end

    it "never retries #{operation} after an ambiguous transport failure" do
      method = :"query_database_#{operation}"
      allow(transport).to receive(method).and_raise(Timeout::Error)
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect { mutation.execute }.to raise_error(Volcano::Error::TransportError)
      expect(transport).to have_received(method).once
      expect(transport).not_to have_received(:auth_refresh)
    end

    it "never retries #{operation} under a replacement session" do
      method = :"query_database_#{operation}"
      allow(transport).to receive(method).and_return(response(401))
      allow(transport).to receive(:auth_refresh) do
        client.auth.current_session = replacement
        refresh_response
      end
      mutation = operation == :delete ? query.delete : query.public_send(operation, 'id' => 1)
      expect { mutation.execute }.to raise_error(Volcano::Error::SessionChangedError)
      expect(transport).to have_received(method).once
      expect(client.current_session).to eq(replacement)
    end
  end
end
