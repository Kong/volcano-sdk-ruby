# frozen_string_literal: true

RSpec.describe Volcano::Durable do
  let(:client) { instance_double(Volcano::Client) }
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:durable) { described_class.new(client, transport) }

  def response
    body = {
      'id' => 'execution', 'function_id' => 'function', 'name' => 'run',
      'status' => 'pending', 'region' => 'aws-us-east-1', 'created_at' => '2026-09-24T00:00:00Z'
    }
    Volcano::Transport::Response.new(status: 202, body: body, headers: {}, data: nil)
  end

  def mutate_on_credential(value)
    allow(client).to receive(:function_token) do
      value.replace('changed')
      'service-key'
    end
  end

  def page_response
    body = { 'data' => [], 'has_more' => false, 'page' => 1, 'limit' => 100, 'total' => 0 }
    Volcano::Transport::Response.new(status: 200, body: body, headers: {}, data: nil)
  end

  it 'snapshots nested payload values before reading the dispatch credential' do
    check_property(PropCheck::Generators.printable_string) do |text|
      value = "original:#{text}"
      payload = { 'nested' => { 'value' => value } }
      sent = nil
      mutate_on_credential(value)
      allow(transport).to receive(:start_durable_execution_from_application) do |payload:, **|
        sent = payload
        response
      end

      durable.start('function', payload)

      expect(sent).to eq('nested' => { 'value' => "original:#{text}" })
      expect(sent.fetch('nested').fetch('value')).to be_frozen
      expect(value).to eq('changed')
    end
  end

  it 'rejects cyclic payloads before reading a credential or dispatching' do
    payload = {}
    payload['self'] = payload
    allow(client).to receive(:function_token)
    allow(transport).to receive(:start_durable_execution_from_application)

    expect { durable.start('function', payload) }.to raise_error(TypeError, 'Request value contains a cycle')
    expect(client).not_to have_received(:function_token)
    expect(transport).not_to have_received(:start_durable_execution_from_application)
  end

  it 'captures the list status before reading the owner credential' do
    status = +'running'
    sent = nil
    allow(client).to receive(:session_token) do
      status.replace('changed')
      'owner-key'
    end
    allow(transport).to receive(:list_durable_executions) do |options:, **|
      sent = options
      page_response
    end

    durable.list('project', 'function', status: status)

    expect(sent).to eq(status: 'running')
    expect(sent.fetch(:status)).to be_frozen
    expect(status).to eq('changed')
  end
end
