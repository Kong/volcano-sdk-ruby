# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'time'

RSpec.describe Volcano::Client do
  Response = Data.define(:status, :body, :headers, :data) unless const_defined?(:Response)

  class FakeContractTransport
    attr_reader :calls
    attr_accessor :access_token

    def initialize
      @access_token = 'access-token'
      @calls = []
    end

    def auth_signin(**arguments)
      @calls << [:auth_signin, arguments]
      Response.new(
        status: 200,
        body: {
          'access_token' => access_token,
          'refresh_token' => 'refresh-token',
          'expires_in' => 3600,
          'user' => { 'id' => 'user-123', 'email' => 'user@example.com', 'status' => 'active' }
        },
        headers: {},
        data: nil
      )
    end

    def query_database_select(**arguments)
      @calls << [:query_database_select, arguments]
      Response.new(status: 200, body: { 'data' => [{ 'slug' => 'a' }] }, headers: {}, data: nil)
    end

    def upload_storage_object(**arguments)
      @calls << [:upload_storage_object, arguments]
      Response.new(status: 201, body: { 'name' => 'a.txt', 'size' => 5 }, headers: {}, data: nil)
    end

    def download_storage_object(**arguments)
      @calls << [:download_storage_object, arguments]
      Response.new(status: 200, body: nil, headers: {}, data: "hello\x00".b)
    end

    def acquire_project_lock(**arguments)
      @calls << [:acquire_project_lock, arguments]
      Response.new(
        status: 201,
        body: { 'expires_at' => Time.iso8601('2026-08-26T12:00:30Z'), 'fencing_token' => 7 },
        headers: {},
        data: nil
      )
    end

    def release_project_lock(**arguments)
      @calls << [:release_project_lock, arguments]
      Response.new(status: 204, body: nil, headers: {}, data: nil)
    end

    def calls_for(name)
      calls.each_with_object([]) do |call, matching|
        matching << call if call.first == name
      end
    end
  end

  let(:transport) { FakeContractTransport.new }
  let(:client) do
    described_class.new(
      api_url: 'https://api.test.volcano.dev',
      anon_key: 'anon-key',
      service_key: 'service-key',
      _transport: transport
    )
  end
  let(:results) do
    session = client.auth.sign_in(email: 'user@example.com', password: 'secret')
    rows = client.database('main').from('items').select('*').eq('slug', 'a').execute
    uploaded = client.storage.from('assets').upload('a.txt', StringIO.new("hello\x00".b))
    downloaded = client.storage.from('assets').download('a.txt')
    lease = client.locks.acquire('build', ttl: 30)
    released = client.locks.release('build', lease)
    {
      session: session,
      rows: rows,
      uploaded: uploaded,
      downloaded: downloaded,
      lease: lease,
      released: released
    }
  end

  it 'returns stable public values from the five facade calls', :aggregate_failures do
    expect(results.fetch(:session)).to eq(
      Volcano::Session.new(
        access_token: 'access-token',
        refresh_token: 'refresh-token',
        expires_in: 3600,
        user_id: 'user-123'
      )
    )
    expect(client.current_session).to be(results.fetch(:session))
    expect(results.fetch(:rows)).to eq([{ 'slug' => 'a' }])
    expect(results.fetch(:uploaded)).to eq({ 'name' => 'a.txt', 'size' => 5 })
    expect(results.fetch(:downloaded)).to eq("hello\x00".b)
    expect(results.fetch(:downloaded).encoding).to eq(Encoding::BINARY)
    expect(results.fetch(:lease)).to eq(
      Volcano::LockLease.new(
        key: 'build',
        token: results.fetch(:lease).token,
        expires_at: Time.iso8601('2026-08-26T12:00:30Z'),
        fencing_token: 7
      )
    )
    expect(results.fetch(:released)).to be_nil
  end

  it 'routes the facade calls through the six contract operations', :aggregate_failures do
    lease = results.fetch(:lease)
    expect(transport.calls.map(&:first)).to eq(
      %i[
        auth_signin
        query_database_select
        upload_storage_object
        download_storage_object
        acquire_project_lock
        release_project_lock
      ]
    )
    expect(transport.calls[0][1]).to eq(
      authorization: 'anon-key',
      email: 'user@example.com',
      password: 'secret'
    )
    expect(transport.calls[1][1]).to eq(
      authorization: 'access-token',
      database_name: 'main',
      body: {
        'table' => 'items',
        'filters' => [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'a' }]
      }
    )
    expect(transport.calls[2][1]).to eq(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'a.txt',
      data: "hello\x00".b
    )
    expect(transport.calls[3][1]).to eq(
      authorization: 'access-token',
      bucket_name: 'assets',
      path: 'a.txt'
    )
    expect(transport.calls[4][1]).to include(
      authorization: 'service-key',
      key: 'build',
      ttl: 30,
      token: lease.token
    )
    expect(transport.calls[5][1]).to include(
      authorization: 'service-key',
      key: 'build',
      token: lease.token
    )
  end

  it 'keeps query chains immutable and reads the latest session at execution time' do
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    base = client.database('main').from('items').select('*')
    first = base.eq('slug', 'first')
    second = base.eq('slug', 'second')

    transport.access_token = 'access-token-2'
    client.auth.sign_in(email: 'user@example.com', password: 'secret')
    first.execute
    second.execute

    query_calls = transport.calls_for(:query_database_select)
    expect(query_calls.map { |_, arguments| arguments[:authorization] }).to eq(
      %w[access-token-2 access-token-2]
    )
    expect(query_calls.map { |_, arguments| arguments[:body]['filters'] }).to eq(
      [
        [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'first' }],
        [{ 'column' => 'slug', 'operator' => 'eq', 'value' => 'second' }]
      ]
    )
  end
end
