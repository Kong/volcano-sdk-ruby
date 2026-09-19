# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Volcano::Client do
  let(:calls) { [] }
  let(:responses) { {} }
  let(:transport) do
    call_log = calls
    replies = responses
    Object.new.tap do |fake|
      %i[
        start_durable_execution_from_application get_durable_execution
        list_durable_executions stop_durable_execution
      ].each do |operation|
        fake.define_singleton_method(operation) do |**arguments|
          call_log << [operation, arguments]
          replies.fetch(operation)
        end
      end
    end
  end
  let(:client) do
    described_class.new(
      anon_key: 'anon-key', service_key: 'service-key', _transport: transport
    )
  end
  let(:owner) do
    client.tap do |value|
      value.auth.current_session = Volcano::Session.new(
        access_token: 'access-token', refresh_token: 'refresh-token', user_id: 'user-1'
      )
    end
  end

  def execution(**overrides)
    {
      'id' => 'execution-1', 'function_id' => 'function-1', 'name' => 'charge-order-9',
      'status' => 'pending', 'region' => 'aws-us-east-1',
      'created_at' => '2026-09-14T12:00:00Z'
    }.merge(overrides.transform_keys(&:to_s))
  end

  def transport_response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  it 'starts an execution and returns its handle', :aggregate_failures do
    responses[:start_durable_execution_from_application] = transport_response(202, execution)

    result = client.durable.start('charge-order', { 'order_id' => 'order-9' })

    expect(result).to have_attributes(
      id: 'execution-1', function_id: 'function-1', name: 'charge-order-9',
      status: 'pending', region: 'aws-us-east-1', created_at: Time.utc(2026, 9, 14, 12),
      result: nil, result_expired: nil, error: nil, completed_at: nil
    )
    expect(result.terminal?).to be(false)
    expect(calls).to eq(
      [[
        :start_durable_execution_from_application,
        {
          authorization: 'service-key', function_id: 'charge-order',
          payload: { 'order_id' => 'order-9' }, execution_name: nil
        }
      ]]
    )
  end

  it 'starts an execution once under one execution name', :aggregate_failures do
    responses[:start_durable_execution_from_application] = transport_response(202, execution)

    first = client.durable.start('charge-order', {}, execution_name: 'order-9')
    again = client.durable.start('charge-order', {}, execution_name: 'order-9')

    expect(again).to eq(first)
    expect(calls.map { |_, arguments| arguments.fetch(:execution_name) }).to eq(%w[order-9 order-9])
    expect(calls.first.last.fetch(:payload)).to eq({})
  end

  it 'prefers a session over the service key' do
    responses[:start_durable_execution_from_application] = transport_response(202, execution)

    owner.durable.start('charge-order')

    expect(calls.first.last.fetch(:authorization)).to eq('access-token')
  end

  it 'uses the anon key without a session or service key' do
    responses[:start_durable_execution_from_application] = transport_response(202, execution)
    public_client = described_class.new(anon_key: 'anon-key', _transport: transport)

    public_client.durable.start('charge-order')

    expect(calls.first.last.fetch(:authorization)).to eq('anon-key')
  end

  it 'reads a succeeded execution and freezes its result', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(
      200,
      execution(
        status: 'succeeded', completed_at: '2026-09-14T12:04:00Z',
        result: { 'charge' => { 'id' => 'charge-1' }, 'items' => [1, 2] }
      )
    )

    result = owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(result).to have_attributes(
      status: 'succeeded', completed_at: Time.utc(2026, 9, 14, 12, 4)
    )
    expect(result.terminal?).to be(true)
    expect(result.result).to eq('charge' => { 'id' => 'charge-1' }, 'items' => [1, 2]).and be_frozen
    expect(result.result.fetch('charge')).to be_frozen
    expect(result.result.fetch('items')).to be_frozen
  end

  it 'records the owner-scoped read', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(200, execution(status: 'running'))

    owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(calls.map(&:first)).to eq([:get_durable_execution])
    expect(calls.first.last).to eq(
      authorization: 'access-token', project_id: 'project-1',
      function_id: 'charge-order', execution_id: 'execution-1'
    )
  end

  it 'surfaces why an execution failed', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(
      200,
      execution(
        status: 'failed', completed_at: '2026-09-14T12:03:00Z',
        error: { 'type' => 'CardDeclined', 'message' => 'card was declined' }
      )
    )

    result = owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(result.error).to have_attributes(type: 'CardDeclined', message: 'card was declined')
    expect(result.terminal?).to be(true)
  end

  it 'distinguishes a discarded result from an empty one', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(
      200, execution(status: 'succeeded', result_expired: true)
    )
    discarded = owner.durable.get('project-1', 'charge-order', 'execution-1')

    responses[:get_durable_execution] = transport_response(
      200, execution(status: 'succeeded', result: nil)
    )
    returned_nothing = owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(discarded).to have_attributes(result: nil, result_expired: true)
    expect(returned_nothing).to have_attributes(result: nil, result_expired: nil)
  end

  it 'treats an undetermined outcome as terminal', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(200, execution(status: 'unknown'))

    result = owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(result.status).to eq('unknown')
    expect(result.terminal?).to be(true)
  end

  it 'lists executions and sends only the options it was given', :aggregate_failures do
    responses[:list_durable_executions] = transport_response(
      200,
      'data' => [execution(status: 'running'), execution(id: 'execution-2', status: 'succeeded')],
      'page' => 1, 'limit' => 10, 'total' => 2, 'has_more' => false
    )

    page = owner.durable.list('project-1', 'charge-order', status: 'running')

    expect(page).to have_attributes(page: 1, limit: 10, total: 2, has_more: false)
    expect(page.executions.map(&:id)).to eq(%w[execution-1 execution-2])
    expect(page.executions).to be_frozen
    expect(calls.first.last).to eq(
      authorization: 'access-token', project_id: 'project-1',
      function_id: 'charge-order', options: { status: 'running' }
    )
  end

  it 'tolerates a page with no executions', :aggregate_failures do
    responses[:list_durable_executions] = transport_response(
      200, 'page' => 2, 'limit' => 10, 'total' => 1, 'has_more' => false
    )

    page = owner.durable.list('project-1', 'charge-order', page: 2, limit: 10)

    expect(page).to have_attributes(executions: [], page: 2, limit: 10, total: 1)
    expect(calls.first.last.fetch(:options)).to eq(page: 2, limit: 10)
  end

  it 'returns the execution read back after asking it to stop', :aggregate_failures do
    responses[:stop_durable_execution] = transport_response(200, execution(status: 'running'))

    result = owner.durable.stop('project-1', 'charge-order', 'execution-1')

    expect(result).to have_attributes(status: 'running')
    expect(result.terminal?).to be(false)
    expect(calls.first.last).to eq(
      authorization: 'access-token', project_id: 'project-1',
      function_id: 'charge-order', execution_id: 'execution-1'
    )
  end

  it 'repeats a stop on a finished execution', :aggregate_failures do
    responses[:stop_durable_execution] = transport_response(
      200, execution(status: 'stopped', completed_at: '2026-09-14T12:02:00Z')
    )

    first = owner.durable.stop('project-1', 'charge-order', 'execution-1')
    again = owner.durable.stop('project-1', 'charge-order', 'execution-1')

    expect(again).to eq(first)
    expect(again.terminal?).to be(true)
  end

  it 'rejects blank path segments before transport', :aggregate_failures do
    ['', '   '].each do |blank|
      expect { client.durable.start(blank) }.to raise_error(ArgumentError, /function_name/)
      expect { client.durable.start('charge-order', {}, execution_name: blank) }
        .to raise_error(ArgumentError, /execution_name/)
      expect { owner.durable.get(blank, 'charge-order', 'execution-1') }
        .to raise_error(ArgumentError, /project_id/)
      expect { owner.durable.get('project-1', blank, 'execution-1') }
        .to raise_error(ArgumentError, /function_name/)
      expect { owner.durable.get('project-1', 'charge-order', blank) }
        .to raise_error(ArgumentError, /execution_id/)
      expect { owner.durable.list('project-1', blank) }.to raise_error(ArgumentError, /function_name/)
      expect { owner.durable.stop('project-1', 'charge-order', blank) }
        .to raise_error(ArgumentError, /execution_id/)
    end

    expect(calls).to be_empty
  end

  # The routes take a user token: list, get and stop sit behind RequireUserAuth,
  # so a service key is answered 401. Sending one would mean a backend holding a
  # platform token never sent it.
  it 'sends the session token for owner-scoped operations', :aggregate_failures do
    responses[:get_durable_execution] = transport_response(200, execution(status: 'running'))

    owner.durable.get('project-1', 'charge-order', 'execution-1')

    expect(calls.first.last.fetch(:authorization)).to eq('access-token')
  end

  it 'requires a platform credential for owner-scoped operations', :aggregate_failures do
    public_client = described_class.new(anon_key: 'anon-key', _transport: transport)

    expect { public_client.durable.get('project-1', 'charge-order', 'execution-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect { public_client.durable.list('project-1', 'charge-order') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect { public_client.durable.stop('project-1', 'charge-order', 'execution-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect(calls).to be_empty
  end

  it 'raises for an execution that does not exist' do
    responses[:get_durable_execution] = transport_response(
      404, 'error' => 'durable execution not found', 'code' => 'execution_not_found'
    )

    expect { owner.durable.get('project-1', 'charge-order', 'execution-1') }
      .to raise_error(Volcano::Error::NotFoundError, 'durable execution not found') do |error|
        expect(error).to have_attributes(status: 404, code: 'execution_not_found')
      end
  end

  it 'raises for a conflicting execution name' do
    responses[:start_durable_execution_from_application] = transport_response(
      409, 'error' => 'execution name is in use', 'code' => 'execution_name_conflict'
    )

    expect { client.durable.start('charge-order', {}, execution_name: 'order-9') }
      .to raise_error(Volcano::Error::ConflictError, 'execution name is in use') do |error|
        expect(error).to have_attributes(status: 409, code: 'execution_name_conflict')
      end
  end

  it 'raises for a platform failure' do
    responses[:start_durable_execution_from_application] = transport_response(
      503, 'error' => 'durable function is provisioning', 'code' => 'function_not_ready'
    )

    expect { client.durable.start('charge-order') }
      .to raise_error(Volcano::Error::ServerError, 'durable function is provisioning') do |error|
        expect(error).to have_attributes(status: 503, code: 'function_not_ready')
      end
  end

  # The generated client validates this header and the paging bounds itself, and
  # answers with its own vocabulary: the operation's name and the option key it
  # knows the header by. A caller reads a message about what they passed
  # instead.
  it 'refuses an execution name the platform would not accept' do
    expect { client.durable.start('charge-order', {}, execution_name: 'order 9') }
      .to raise_error(ArgumentError, /execution_name must be 1-255 characters/)
  end

  it 'refuses paging arguments outside what the API serves' do
    expect { client.durable.list('project-1', 'charge-order', limit: 101) }
      .to raise_error(ArgumentError, /limit must be an Integer between 1 and 100/)
    expect { client.durable.list('project-1', 'charge-order', page: 0) }
      .to raise_error(ArgumentError, /page must be a positive Integer/)
  end
end
