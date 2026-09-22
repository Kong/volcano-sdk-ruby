# frozen_string_literal: true

RSpec.describe Volcano::Durable do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }

  def execution
    {
      'id' => 'execution', 'function_id' => 'function', 'name' => 'job',
      'status' => 'running', 'region' => 'aws-us-east-1', 'created_at' => '2026-01-01T00:00:00Z'
    }
  end

  def response(payload)
    Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil)
  end

  [nil, [], 'invalid', {}].each do |payload|
    it "rejects a malformed execution payload #{payload.inspect}" do
      allow(transport).to receive(:get_durable_execution).and_return(response(payload))

      expect { client.durable.get('project', 'function', 'execution') }
        .to raise_error(TypeError, 'Expected a complete durable execution')
    end
  end

  [{ 'created_at' => nil }, { 'error' => 'failure' }, { 'status' => ' ' }].each do |fields|
    it "rejects malformed execution fields #{fields.inspect}" do
      allow(transport).to receive(:get_durable_execution).and_return(response(execution.merge(fields)))

      expect { client.durable.get('project', 'function', 'execution') }
        .to raise_error(TypeError, 'Expected a complete durable execution')
    end
  end

  [nil, [], { 'data' => {} }, { 'has_more' => 'false' }, { 'page' => '1' }].each do |payload|
    it "rejects a malformed execution page #{payload.inspect}" do
      allow(transport).to receive(:list_durable_executions).and_return(response(payload))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end
  end

  it 'preserves a complete empty page' do
    payload = { 'data' => [], 'page' => 1, 'limit' => 20, 'total' => 0, 'has_more' => false }
    allow(transport).to receive(:list_durable_executions).and_return(response(payload))

    expect(client.durable.list('project', 'function'))
      .to have_attributes(executions: [], page: 1, limit: 20, total: 0, has_more: false)
  end

  it 'defaults omitted page counts to zero' do
    allow(transport).to receive(:list_durable_executions).and_return(response({}))

    expect(client.durable.list('project', 'function'))
      .to have_attributes(executions: [], page: 0, limit: 0, total: 0, has_more: false)
  end
end
