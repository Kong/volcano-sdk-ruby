# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:calls) { [] }
  let(:responses) { {} }
  let(:transport) do
    call_log = calls
    replies = responses
    Object.new.tap do |fake|
      %i[send_durable_message list_durable_messages].each do |operation|
        fake.define_singleton_method(operation) do |**arguments|
          call_log << [operation, arguments]
          replies.fetch(operation)
        end
      end
    end
  end
  let(:client) { described_class.new(anon_key: 'anon-key', _transport: transport) }
  let(:messages) { client.durable.messages }

  def owner_messages
    described_class.new(anon_key: 'anon-key', access_token: 'platform-token', _transport: transport).durable.messages
  end

  def message(**overrides)
    {
      'id' => 'message-1', 'execution_id' => 'execution-1', 'direction' => 'in', 'seq' => 4,
      'name' => 'decision', 'data' => { 'approved' => true }, 'sender' => { 'type' => 'anon', 'user_id' => nil },
      'status' => 'queued', 'delivered_at' => nil, 'sent_at' => '2026-10-12T09:00:00Z'
    }.merge(overrides.transform_keys(&:to_s))
  end

  def transport_response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  def target(**overrides)
    { project_id: nil, function_id: 'approvals', execution_id: 'execution-1', client_token: nil }.merge(overrides)
  end

  def sent_target
    calls.first.last.fetch(:target).to_h
  end

  it 'sends a message on the application route with the client credential', :aggregate_failures do
    responses[:send_durable_message] = transport_response(201, message)

    result = messages.send_message('approvals', 'execution-1', 'decision', { 'approved' => true })

    expect(result).to have_attributes(
      id: 'message-1', execution_id: 'execution-1', direction: 'in', seq: 4, name: 'decision',
      data: { 'approved' => true }, status: 'queued', delivered_at: nil, sent_at: Time.utc(2026, 10, 12, 9)
    )
    expect(result.sender).to eq(Volcano::DurableMessageSender.new(type: 'anon'))
    expect(result.data).to be_frozen
    arguments = calls.first.last
    expect(arguments.except(:target)).to eq(
      authorization: 'anon-key', name: 'decision', data: { 'approved' => true }, idempotency_key: nil
    )
    expect(sent_target).to eq(target)
  end

  it 'sends the client token and idempotency key it is given' do
    responses[:send_durable_message] = transport_response(201, message)

    messages.send_message(
      'approvals', 'execution-1', 'decision', nil, idempotency_key: 'decision-1', client_token: 'client-token'
    )

    expect(calls.first.last).to include(idempotency_key: 'decision-1', data: nil)
    expect(sent_target).to eq(target(client_token: 'client-token'))
  end

  it 'masks the client token wherever a message target is inspected', :aggregate_failures do
    responses[:send_durable_message] = transport_response(201, message)

    messages.send_message('approvals', 'execution-1', 'decision', nil, client_token: 'client-token')

    sent = calls.first.last.fetch(:target)
    shown = '#<data Volcano::DurableMessages::Target project_id=nil, function_id="approvals", ' \
            'execution_id="execution-1", client_token=[REDACTED]>'
    expect(sent.inspect).to eq(shown)
    expect(sent.to_s).to eq(shown)
    expect(PP.pp(sent, +'')).to eq("#{shown}\n")
    expect(sent.with(client_token: nil).inspect).to end_with('client_token=nil>')
  end

  it 'sends on the project route with the session token when given a project' do
    responses[:send_durable_message] = transport_response(201, message(sender: { 'type' => 'project' }))

    result = owner_messages.send_message('approvals', 'execution-1', 'decision', 'yes', project_id: 'project-1')

    expect(result.sender.type).to eq('project')
    expect(calls.first.last.fetch(:authorization)).to eq('platform-token')
    expect(sent_target).to eq(target(project_id: 'project-1'))
  end

  it 'returns the stored message when an idempotency key repeats' do
    responses[:send_durable_message] = transport_response(200, message(status: 'delivered',
                                                                       delivered_at: '2026-10-12T09:00:01Z'))

    result = messages.send_message('approvals', 'execution-1', 'decision', {}, idempotency_key: 'decision-1')

    expect(result).to have_attributes(status: 'delivered', delivered_at: Time.utc(2026, 10, 12, 9, 0, 1))
  end

  it 'owns a copy of the data it sends' do
    responses[:send_durable_message] = transport_response(201, message)
    data = { 'note' => +'ship' }

    messages.send_message('approvals', 'execution-1', 'decision', data)
    data.fetch('note').replace('changed')

    expect(calls.first.last.fetch(:data)).to eq('note' => 'ship').and be_frozen
  end

  it 'raises a conflict when the execution has ended' do
    responses[:send_durable_message] = transport_response(
      409, 'error' => 'execution is not running', 'code' => 'execution_not_running'
    )

    expect { messages.send_message('approvals', 'execution-1', 'decision') }
      .to raise_error(Volcano::Error::ConflictError, 'execution is not running') do |error|
        expect(error).to have_attributes(status: 409, code: 'execution_not_running')
      end
  end

  it 'raises for an execution the credential cannot reach' do
    responses[:send_durable_message] = transport_response(404, 'error' => 'durable execution not found')

    expect { messages.send_message('approvals', 'execution-1', 'decision') }
      .to raise_error(Volcano::Error::NotFoundError, 'durable execution not found')
  end

  it 'lists messages with every filter as the query', :aggregate_failures do
    responses[:list_durable_messages] = transport_response(200, 'data' => [message], 'has_more' => true)

    page = messages.list('approvals', 'execution-1', direction: :in, name: 'decision', after: 0, limit: 500,
                                                     client_token: 'client-token')

    expect(page).to have_attributes(has_more: true)
    expect(page.messages.map(&:id)).to eq(['message-1'])
    expect(page.messages).to be_frozen
    expect(calls.first.last.except(:target)).to eq(
      authorization: 'anon-key', query: { direction: 'in', name: 'decision', after: 0, limit: 500 }
    )
    expect(sent_target).to eq(target(client_token: 'client-token'))
  end

  it 'lists without filters by sending an empty query' do
    responses[:list_durable_messages] = transport_response(200, 'data' => [], 'has_more' => false)

    expect(owner_messages.list('approvals', 'execution-1', { project_id: 'project-1' }))
      .to have_attributes(messages: [], has_more: false)
    expect(calls.first.last).to include(authorization: 'platform-token', query: {})
    expect(sent_target).to eq(target(project_id: 'project-1'))
  end

  it 'requires a session for the project route' do
    expect { messages.send_message('approvals', 'execution-1', 'decision', project_id: 'project-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect { messages.list('approvals', 'execution-1', project_id: 'project-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect(calls).to be_empty
  end

  it 'rejects blank path segments before transport', :aggregate_failures do
    ['', '  ', nil].each do |blank|
      expect { messages.send_message(blank, 'execution-1', 'decision') }.to raise_error(ArgumentError, /function_name/)
      expect { messages.list('approvals', blank) }.to raise_error(ArgumentError, /execution_id/)
    end
    expect { messages.list('approvals', 'execution-1', project_id: ' ') }.to raise_error(ArgumentError, /project_id/)
    expect(calls).to be_empty
  end

  it 'refuses names, keys, and tokens the API would not accept', :aggregate_failures do
    ['', 'n' * 238, "line\nbreak", 'café', :decision].each do |name|
      expect { messages.send_message('approvals', 'execution-1', name) }
        .to raise_error(ArgumentError, 'name must be 1 to 237 printable ASCII characters')
    end
    expect { messages.list('approvals', 'execution-1', name: '') }.to raise_error(ArgumentError, /name must be/)
    ['', 'k' * 256, 'confirm-café', "line\nbreak"].each do |key|
      expect { messages.send_message('approvals', 'execution-1', 'decision', idempotency_key: key) }
        .to raise_error(ArgumentError, 'idempotency_key must be 1 to 255 printable ASCII characters')
    end
    ['t' * 129, 'tök', 7].each do |token|
      expect { messages.list('approvals', 'execution-1', client_token: token) }
        .to raise_error(ArgumentError, 'client_token must be 1 to 128 printable ASCII characters')
    end
    expect(calls).to be_empty
  end

  it 'accepts values at their limits' do
    responses[:send_durable_message] = transport_response(201, message)

    name = "#{' ~' * 118}x"
    messages.send_message('approvals', 'execution-1', name, idempotency_key: 'k' * 255, client_token: 't' * 128)

    expect(calls.first.last).to include(name: name, idempotency_key: 'k' * 255)
  end

  it 'refuses list filters the API would not accept', :aggregate_failures do
    expect { messages.list('approvals', 'execution-1', direction: 'both') }
      .to raise_error(ArgumentError, "direction must be 'in' or 'out'")
    expect { messages.list('approvals', 'execution-1', after: -1) }
      .to raise_error(ArgumentError, 'after must be a non-negative Integer')
    expect { messages.list('approvals', 'execution-1', after: '3') }.to raise_error(ArgumentError, /after/)
    [0, 501, 2.5].each do |limit|
      expect { messages.list('approvals', 'execution-1', limit: limit) }
        .to raise_error(ArgumentError, 'limit must be an Integer between 1 and 500')
    end
    expect(calls).to be_empty
  end

  it 'refuses an option it does not know, as an unknown keyword', :aggregate_failures do
    expect { messages.send_message('approvals', 'execution-1', 'decision', key: 'k') }
      .to raise_error(ArgumentError, 'unknown keywords: key')
    expect { messages.list('approvals', 'execution-1', before: 3, limit: 1) }
      .to raise_error(ArgumentError, 'unknown keywords: before')
    expect { messages.list('approvals', 'execution-1', 'out') }.to raise_error(TypeError, 'filters must be a Hash')
    expect(calls).to be_empty
  end
end
