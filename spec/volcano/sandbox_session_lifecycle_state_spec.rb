# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::SandboxSession do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', service_key: 'service', _transport: transport) }
  let(:id) { '00000000-0000-4000-8000-000000000001' }
  let(:payload) do
    { 'id' => id, 'project_id' => id, 'region' => 'us-east-1',
      'state' => +'running', 'expires_at' => '2026-10-06T10:00:00Z' }
  end

  before do
    responses = [
      Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil),
      Volcano::Transport::Response.new(status: 202, body: payload.merge('state' => 'terminating'),
                                       headers: {}, data: nil)
    ]
    allow(transport).to receive(:sandbox_request).and_return(*responses)
  end

  def expect_termination
    expect(transport).to have_received(:sandbox_request).with(
      authorization: 'service', request: have_attributes(operation: :terminate_sandbox_session)
    ).once
  end

  it 'rejects caller state mutation and still cleans up the session' do
    handle = client.sandboxes.get(id)
    expect { handle.use { |session| session.state.replace('terminated') } }.to raise_error(FrozenError)
    expect_termination
    expect(handle.state).to eq('terminating')
  end

  it 'owns its state without freezing or retaining the mutable response string' do
    handle = client.sandboxes.get(id)
    payload.fetch('state').replace('terminated')
    expect(handle.state).to eq('running')
    expect(handle.use(&:id)).to eq(id)
    expect_termination
    expect(handle.state).to eq('terminating')
  end
end
