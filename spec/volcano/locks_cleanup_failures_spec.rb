# frozen_string_literal: true

require_relative '../support/fake_lock_transport'

RSpec.describe Volcano::Locks do
  let(:transport) { SpecSupport::FakeLockTransport.new }
  let(:client) { Volcano::Client.new(anon_key: 'anon', service_key: 'service', _transport: transport) }
  let(:locks) { client.locks }

  before do
    transport.release_handler = ->(_) { transport.response(500, 'message' => 'release failed') }
  end

  it 'reports a release failure after successful work' do
    expect { locks.with_lock('build', ttl: 30) { :completed } }
      .to raise_error(Volcano::Error::ServerError, 'release failed')
    expect(transport.calls.map(&:first)).to eq(%i[acquire_project_lock release_project_lock])
  end

  it 'preserves the exact body failure when release also fails' do
    failure = RuntimeError.new('body failed')

    expect { locks.with_lock('build', ttl: 30) { raise failure } }.to(raise_error do |error|
      expect(error).to equal(failure)
    end)
    expect(transport.calls.last.first).to eq(:release_project_lock)
  end

  it 'reports ownership loss before a later release failure' do
    failure = Timeout::Error.new('lease lost')

    expect do
      locks.with_lock('build', ttl: 30) { |guard| guard.mark_lost(failure) }
    end.to(raise_error { |error| expect(error).to equal(failure) })
    expect(transport.calls.last.first).to eq(:release_project_lock)
  end

  it 'preserves the body failure over ownership loss and a release failure' do
    failure = RuntimeError.new('body failed')

    expect do
      locks.with_lock('build', ttl: 30) do |guard|
        guard.mark_lost(Timeout::Error.new('lease lost'))
        raise failure
      end
    end.to(raise_error { |error| expect(error).to equal(failure) })
    expect(transport.calls.last.first).to eq(:release_project_lock)
  end
end
