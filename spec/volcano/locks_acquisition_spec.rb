# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Locks do
  subject(:locks) { described_class.new(client, transport) }

  let(:client) { Struct.new(:service_token).new('service-key') }
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:owner_token) { '00000000-0000-4000-8000-000000000001' }
  let(:request_id) { '00000000-0000-4000-8000-000000000002' }
  let(:lease_body) { { 'expires_at' => '2026-09-18T18:00:00Z', 'fencing_token' => 7 } }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  %i[transport unavailable].product([false, true]).each do |failure, supplied|
    it "reuses one ownership token and request ID after #{failure}, supplied: #{supplied}" do
      calls = []
      allow(transport).to receive(:acquire_project_lock) do |**arguments|
        calls << arguments
        if calls.length == 1
          raise IOError, 'response lost' if failure == :transport

          next response(503, 'error' => 'outcome unknown')
        end
        response(201, lease_body)
      end
      options = supplied ? { token: owner_token, request_id: request_id } : {}
      lease = locks.acquire('build', ttl: 30, **options)
      expect(calls.length).to eq(2)
      expect(calls[0]).to eq(calls[1])
      expect(lease.token).to eq(calls[0].fetch(:token))
      expect(calls[0]).to include(token: owner_token, request_id: request_id) if supplied
    end
  end

  [[400, 1], [401, 1], [403, 1], [409, 1], [429, 1], [500, 1], [503, 2]].each do |status, attempts|
    it "bounds retries for status #{status} and preserves its typed error" do
      allow(transport).to receive(:acquire_project_lock).and_return(response(status, 'error' => 'rejected'))
      expect { locks.acquire('build', ttl: 30, token: owner_token, request_id: request_id) }
        .to raise_error(Volcano::Error::VolcanoError) { |error| expect(error.status).to eq(status) }
      expect(transport).to have_received(:acquire_project_lock).exactly(attempts).times
    end
  end

  it 'stops after two ambiguous transport failures' do
    allow(transport).to receive(:acquire_project_lock).and_raise(IOError, 'response lost')
    expect { locks.acquire('build', ttl: 30, token: owner_token, request_id: request_id) }
      .to raise_error(Volcano::Error::TransportError)
    expect(transport).to have_received(:acquire_project_lock)
      .with(authorization: 'service-key', key: 'build', ttl: 30, token: owner_token, request_id: request_id).twice
  end

  %i[token request_id].product(['', 'not-a-uuid']).each do |name, value|
    it "rejects invalid #{name} #{value.inspect} before a request" do
      expect { locks.acquire('build', ttl: 30, **{ name => value }) }.to raise_error(ArgumentError, /#{name}/)
    end
  end
  it 'copies the original request before a retry can observe caller changes' do
    key = +'build'
    calls = []
    allow(transport).to receive(:acquire_project_lock) do |**arguments|
      calls << arguments
      key.replace('other')
      client.service_token = 'replacement'
      calls.length == 1 ? response(503, 'error' => 'unknown') : response(201, lease_body)
    end
    lease = locks.acquire(key, ttl: 30, token: owner_token, request_id: request_id)
    expect(calls).to eq([calls.first, calls.first])
    expect(calls.first).to include(key: 'build', authorization: 'service-key', token: owner_token,
                                   request_id: request_id)
    expect(lease.key).to eq('build')
  end
end
