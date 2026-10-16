# frozen_string_literal: true

RSpec.describe Volcano::DurableMessages do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', _transport: transport) }
  let(:messages) { client.durable.messages }

  def message
    {
      'id' => 'message', 'execution_id' => 'execution', 'direction' => 'out', 'seq' => 1, 'name' => 'progress',
      'data' => [1, 'two'], 'sender' => { 'type' => 'execution', 'user_id' => nil }, 'status' => 'published',
      'delivered_at' => nil, 'sent_at' => '2026-10-12T09:00:00Z'
    }
  end

  def response(payload, status: 200)
    Volcano::Transport::Response.new(status: status, body: payload, headers: {}, data: nil)
  end

  def sent(payload)
    allow(transport).to receive(:send_durable_message).and_return(response(payload, status: 201))
    messages.send_message('approvals', 'execution', 'decision')
  end

  def listed(payload)
    allow(transport).to receive(:list_durable_messages).and_return(response(payload))
    messages.list('approvals', 'execution')
  end

  [nil, [], 'invalid', {}].each do |payload|
    it "rejects a malformed message payload #{payload.inspect}" do
      expect { sent(payload) }.to raise_error(TypeError, 'Expected a complete durable message')
    end
  end

  [
    { 'id' => nil }, { 'execution_id' => '' }, { 'name' => 7 }, { 'direction' => 'both' }, { 'direction' => :out },
    { 'seq' => 0 }, { 'seq' => '1' }, { 'seq' => 1.0 }, { 'status' => '' }, { 'status' => :queued },
    { 'status' => nil }, { 'data' => Object.new },
    { 'data' => { key: 'symbol' } }, { 'sender' => nil }, { 'sender' => { 'type' => '' } },
    { 'sender' => { 'type' => 'user', 'user_id' => 7 } }, { 'sent_at' => nil }, { 'sent_at' => 'today' },
    { 'delivered_at' => 12 }
  ].each do |fields|
    it "rejects malformed message fields #{fields.inspect}" do
      expect { sent(message.merge(fields)) }.to raise_error(TypeError, 'Expected a complete durable message')
    end
  end

  it 'reads a message without data, and one delivered to a user', :aggregate_failures do
    received = sent(message.except('data').merge(
                      'direction' => 'in', 'status' => 'delivered', 'delivered_at' => '2026-10-12T09:00:01Z',
                      'sender' => { 'type' => 'user', 'user_id' => 'user-1' }
                    ))

    expect(received).to have_attributes(data: nil, delivered_at: Time.utc(2026, 10, 12, 9, 0, 1))
    expect(received.sender).to have_attributes(type: 'user', user_id: 'user-1')
  end

  it 'reads a status this version does not know as written' do
    expect(listed('data' => [message.merge('status' => 'archived')], 'has_more' => false).messages.first.status)
      .to eq('archived')
  end

  [nil, [], 'invalid', {}, { 'data' => {}, 'has_more' => false }, { 'data' => [], 'has_more' => nil },
   { 'data' => [], 'has_more' => 'false' }].each do |payload|
    it "rejects a malformed message page #{payload.inspect}" do
      expect { listed(payload) }.to raise_error(TypeError, 'Expected a complete durable message page')
    end
  end

  it 'rejects a page with a malformed message' do
    expect { listed('data' => [message.merge('seq' => -1)], 'has_more' => false) }
      .to raise_error(TypeError, 'Expected a complete durable message')
  end

  def started(client_token)
    execution = {
      'id' => 'execution', 'function_id' => 'function', 'name' => 'job', 'status' => 'pending',
      'region' => 'aws-us-east-1', 'created_at' => '2026-10-12T09:00:00Z', 'client_token' => client_token
    }
    allow(transport).to receive(:start_durable_execution_from_application)
      .and_return(response(execution, status: 202))
    client.durable.start('approvals')
  end

  it 'reads a null client token as none' do
    expect(started(nil).client_token).to be_nil
  end

  ['', 12].each do |token|
    it "rejects an execution whose client token is #{token.inspect}" do
      expect { started(token) }.to raise_error(TypeError, 'Expected a complete durable execution')
    end
  end
end
