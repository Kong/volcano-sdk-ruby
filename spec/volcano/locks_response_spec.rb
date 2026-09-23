# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/facade/fake_lock_transport'
require_relative '../support/recording_server'

RSpec.describe Volcano::Locks do
  subject(:locks) { described_class.new(client, transport) }

  let(:client) { instance_double(Volcano::Client, service_token: 'service-key') }
  let(:transport) { instance_double(SpecSupport::Facade::FakeLockTransport) }

  def response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  it 'rejects a non-object lock state response' do
    allow(transport).to receive(:get_project_lock).and_return(response(200, 'broken'))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock response')
  end

  it 'rejects an invalid held flag' do
    allow(transport).to receive(:get_project_lock).and_return(response(200, 'held' => 'yes'))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock held flag')
  end

  it 'accepts an unheld lock without an expiry or fencing token' do
    allow(transport).to receive(:get_project_lock).and_return(response(200, 'held' => false))

    expect(locks.get('build')).to eq(Volcano::LockState.new(held: false, expires_at: nil, fencing_token: nil))
  end

  it 'preserves an optional fencing token on an unheld lock' do
    allow(transport).to receive(:get_project_lock).and_return(response(200, 'held' => false, 'fencing_token' => 7))

    expect(locks.get('build').fencing_token).to eq(7)
  end

  it 'rejects a held lock without an expiry' do
    allow(transport).to receive(:get_project_lock).and_return(response(200, 'held' => true, 'fencing_token' => 7))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock expiry')
  end

  it 'rejects a held lock without a fencing token' do
    body = { 'held' => true, 'expires_at' => '2026-09-23T00:00:00Z' }
    allow(transport).to receive(:get_project_lock).and_return(response(200, body))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock fencing token')
  end

  it 'accepts a parsed expiry from a transport adapter' do
    expiry = Time.utc(2026, 9, 23)
    body = { 'held' => true, 'expires_at' => expiry, 'fencing_token' => 7 }
    allow(transport).to receive(:get_project_lock).and_return(response(200, body))

    expect(locks.get('build').expires_at).to eq(expiry)
  end

  it 'rejects a malformed lock expiry' do
    body = { 'held' => true, 'expires_at' => [], 'fencing_token' => 7 }
    allow(transport).to receive(:get_project_lock).and_return(response(200, body))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock expiry')
  end

  it 'rejects a malformed expiry string as a transport error' do
    body = { 'held' => true, 'expires_at' => 'not-a-time', 'fencing_token' => 7 }
    allow(transport).to receive(:get_project_lock).and_return(response(200, body))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock expiry')
  end

  it 'rejects a malformed fencing token' do
    body = { 'held' => true, 'expires_at' => '2026-09-23T00:00:00Z', 'fencing_token' => 'seven' }
    allow(transport).to receive(:get_project_lock).and_return(response(200, body))

    expect { locks.get('build') }.to raise_error(Volcano::Error::TransportError, 'invalid lock fencing token')
  end

  it 'bounds retries on a malformed acquisition response' do
    allow(transport).to receive(:acquire_project_lock).and_return(response(201, nil))

    expect { locks.acquire('build', ttl: 30) }
      .to raise_error(Volcano::Error::TransportError, 'invalid lock response')
    expect(transport).to have_received(:acquire_project_lock).twice
  end

  it 'rejects an acquired lease without a fencing token' do
    body = { 'expires_at' => '2026-09-23T00:00:00Z' }
    allow(transport).to receive(:acquire_project_lock).and_return(response(201, body))

    expect { locks.acquire('build', ttl: 30) }
      .to raise_error(Volcano::Error::TransportError, 'invalid lock fencing token')
  end

  it 'rejects an acquired lease without an expiry' do
    allow(transport).to receive(:acquire_project_lock).and_return(response(201, 'fencing_token' => 7))

    expect { locks.acquire('build', ttl: 30) }
      .to raise_error(Volcano::Error::TransportError, 'invalid lock expiry')
  end

  it 'rejects a renewed lease without an expiry' do
    lease = Volcano::LockLease.new(key: 'build', token: 'owner', expires_at: Time.now, fencing_token: 7)
    allow(transport).to receive(:renew_project_lock).and_return(response(200, 'fencing_token' => 7))

    expect { locks.renew('build', lease, ttl: 30) }
      .to raise_error(Volcano::Error::TransportError, 'invalid lock expiry')
  end

  it 'validates malformed booleans from the real generated HTTP path' do
    server = RecordingServer.new { [200, { 'held' => 'yes' }, {}] }
    client = Volcano::Client.new(anon_key: 'anon', service_key: 'service', api_url: server.url)

    expect { client.locks.get('build') }
      .to raise_error(Volcano::Error::TransportError, 'invalid lock held flag')
  ensure
    server&.close
  end
end
