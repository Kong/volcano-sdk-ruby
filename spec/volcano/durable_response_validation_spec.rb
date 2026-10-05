# frozen_string_literal: true

RSpec.describe Volcano::Durable do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }
  let(:empty_page) { { 'data' => [], 'page' => 1, 'limit' => 20, 'total' => 0, 'has_more' => false } }

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

  [{ 'created_at' => nil }, { 'error' => 'failure' }, { 'status' => ' ' },
   { 'id' => nil }, { 'created_at' => 12 }, { 'completed_at' => 12 },
   { 'result_expired' => 'false' }, { 'result' => Object.new },
   { 'result' => { status: 'done' } }].each do |fields|
    it "rejects malformed execution fields #{fields.inspect}" do
      allow(transport).to receive(:get_durable_execution).and_return(response(execution.merge(fields)))

      expect { client.durable.get('project', 'function', 'execution') }
        .to raise_error(TypeError, 'Expected a complete durable execution')
    end
  end

  it 'preserves a timestamp object in an execution response' do
    timestamp = Time.utc(2026)
    allow(transport).to receive(:get_durable_execution)
      .and_return(response(execution.merge('created_at' => timestamp)))

    expect(client.durable.get('project', 'function', 'execution').created_at).to eq(timestamp)
  end

  [nil, [], 'invalid', {}].each do |payload|
    it "rejects a malformed execution page #{payload.inspect}" do
      allow(transport).to receive(:list_durable_executions).and_return(response(payload))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end
  end

  invalid_page_values = [nil, 'invalid', {}]
  %w[data page limit total has_more].each do |field|
    it "rejects a page without #{field}" do
      allow(transport).to receive(:list_durable_executions).and_return(response(empty_page.except(field)))

      expect { client.durable.list('project', 'function') }
        .to raise_error(TypeError, 'Expected a complete durable execution page')
    end

    invalid_page_values.each do |value|
      it "rejects a page with #{field} set to #{value.inspect}" do
        allow(transport).to receive(:list_durable_executions).and_return(response(empty_page.merge(field => value)))

        expect { client.durable.list('project', 'function') }
          .to raise_error(TypeError, 'Expected a complete durable execution page')
      end
    end
  end

  it 'preserves a complete empty page' do
    allow(transport).to receive(:list_durable_executions).and_return(response(empty_page))

    expect(client.durable.list('project', 'function'))
      .to have_attributes(executions: [], page: 1, limit: 20, total: 0, has_more: false)
  end
end
