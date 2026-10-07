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
        list_durable_approvals get_durable_approval get_durable_approval_stats
        approve_durable_approval deny_durable_approval
      ].each do |operation|
        fake.define_singleton_method(operation) do |**arguments|
          call_log << [operation, arguments]
          replies.fetch(operation)
        end
      end
    end
  end
  let(:client) do
    described_class.new(anon_key: 'anon-key', access_token: 'platform-token', _transport: transport)
  end
  let(:approvals) { client.durable.approvals }

  def approval(**overrides)
    {
      'id' => 'approval-1', 'status' => 'pending', 'name' => 'ship-order',
      'title' => 'Ship order 1234?', 'description' => '', 'details' => { 'order_id' => 1234 },
      'function' => { 'id' => 'function-1', 'name' => 'order-pipeline' },
      'execution' => { 'id' => 'execution-1', 'name' => 'order-1234', 'status' => 'running' },
      'requested_at' => '2026-10-06T12:00:00Z', 'expires_at' => '2026-10-07T12:00:00Z', 'decision' => nil
    }.merge(overrides.transform_keys(&:to_s))
  end

  def decided(status, comment)
    approval(
      status: status,
      decision: {
        'comment' => comment, 'decided_by' => { 'id' => 'user-1', 'email' => 'ops@example.com' },
        'decided_at' => '2026-10-06T12:05:00Z'
      }
    )
  end

  def counts(requested)
    { 'requested' => requested, 'pending' => 1, 'approved' => 2, 'denied' => 1, 'expired' => 0, 'cancelled' => 0 }
  end

  def transport_response(status, body)
    Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
  end

  it 'reads an approval with its workflow, execution and details', :aggregate_failures do
    responses[:get_durable_approval] = transport_response(200, approval)

    result = approvals.get('project-1', 'approval-1')

    expect(result).to have_attributes(
      id: 'approval-1', status: 'pending', name: 'ship-order', title: 'Ship order 1234?',
      description: '', details: { 'order_id' => 1234 }, decision: nil,
      requested_at: Time.utc(2026, 10, 6, 12), expires_at: Time.utc(2026, 10, 7, 12)
    )
    expect(result.function).to eq(Volcano::DurableApprovalFunction.new(id: 'function-1', name: 'order-pipeline'))
    expect(result.execution).to have_attributes(id: 'execution-1', name: 'order-1234', status: 'running')
    expect(result.details).to be_frozen
    expect(calls).to eq(
      [[:get_durable_approval, { authorization: 'platform-token', project_id: 'project-1', approval_id: 'approval-1' }]]
    )
  end

  # The function and execution outlive neither deletion nor retention, and the
  # person who decided can delete their account; their names stay.
  it 'keeps an approval whose workflow, execution and decider are gone', :aggregate_failures do
    decision = { 'comment' => 'ok', 'decided_by' => nil, 'decided_at' => '2026-10-06T12:05:00Z' }
    responses[:get_durable_approval] = transport_response(
      200, approval(
        status: 'approved', expires_at: nil, decision: decision,
        function: { 'id' => nil, 'name' => 'order-pipeline' },
        execution: { 'id' => nil, 'name' => 'order-1234', 'status' => nil }
      ).except('details')
    )

    result = approvals.get('project-1', 'approval-1')

    expect(result).to have_attributes(status: 'approved', expires_at: nil, details: nil)
    expect(result.function).to have_attributes(id: nil, name: 'order-pipeline')
    expect(result.execution).to have_attributes(id: nil, name: 'order-1234', status: nil)
    expect(result.decision).to have_attributes(comment: 'ok', decided_by: nil, decided_at: Time.utc(2026, 10, 6, 12, 5))
  end

  it 'lists approvals with every filter as query options', :aggregate_failures do
    responses[:list_durable_approvals] = transport_response(
      200, 'data' => [approval], 'page' => 2, 'limit' => 10, 'total' => 11, 'has_more' => false
    )

    page = approvals.list(
      'project-1', status: 'pending', function: 'order-pipeline', execution_id: 'execution-1',
                   from: Time.utc(2026, 10, 1), to: '2026-10-06T00:00:00+02:00', page: 2, limit: 10
    )

    expect(page).to have_attributes(page: 2, limit: 10, total: 11, has_more: false)
    expect(page.approvals.map(&:id)).to eq(['approval-1'])
    expect(calls.first).to eq(
      [:list_durable_approvals, {
        authorization: 'platform-token', project_id: 'project-1',
        options: {
          status: 'pending', function: 'order-pipeline', execution_id: 'execution-1',
          from: '2026-10-01T00:00:00.000000000Z', to: '2026-10-05T22:00:00.000000000Z', page: 2, limit: 10
        }
      }]
    )
  end

  it 'lists without filters by sending no options' do
    responses[:list_durable_approvals] = transport_response(
      200, 'data' => [], 'page' => 1, 'limit' => 20, 'total' => 0, 'has_more' => false
    )

    expect(approvals.list('project-1')).to have_attributes(approvals: [], total: 0)
    expect(calls.first.last.fetch(:options)).to eq({})
  end

  it 'reads approval statistics for a window', :aggregate_failures do
    responses[:get_durable_approval_stats] = transport_response(
      200,
      'from' => '2026-09-06T00:00:00Z', 'to' => '2026-10-06T00:00:00Z', 'counts' => counts(4),
      'approval_rate' => 0.5, 'median_seconds_to_decision' => 12, 'p90_seconds_to_decision' => 30.5,
      'functions' => [{ 'function' => { 'id' => nil, 'name' => 'order-pipeline' }, 'counts' => counts(4) }],
      'other_functions' => counts(0), 'daily' => [{ 'date' => '2026-10-06', 'counts' => counts(4) }]
    )

    stats = approvals.stats('project-1', function: 'order-pipeline', from: Time.utc(2026, 9, 6))

    expect(stats).to have_attributes(
      from: Time.utc(2026, 9, 6), to: Time.utc(2026, 10, 6), approval_rate: 0.5,
      median_seconds_to_decision: 12.0, p90_seconds_to_decision: 30.5
    )
    expect(stats.counts).to eq(
      Volcano::DurableApprovalCounts.new(requested: 4, pending: 1, approved: 2, denied: 1, expired: 0, cancelled: 0)
    )
    expect(stats.functions.first.function).to have_attributes(id: nil, name: 'order-pipeline')
    expect(stats.other_functions.requested).to eq(0)
    expect(stats.daily.first).to have_attributes(date: '2026-10-06', counts: stats.counts)
    expect(calls.first.last).to eq(
      authorization: 'platform-token', project_id: 'project-1',
      options: { function: 'order-pipeline', from: '2026-09-06T00:00:00.000000000Z' }
    )
  end

  it 'reports no rate or timing while nothing was decided' do
    responses[:get_durable_approval_stats] = transport_response(
      200,
      'from' => '2026-09-06T00:00:00Z', 'to' => '2026-10-06T00:00:00Z', 'counts' => counts(0),
      'approval_rate' => nil, 'median_seconds_to_decision' => nil, 'p90_seconds_to_decision' => nil,
      'functions' => [], 'other_functions' => counts(0), 'daily' => []
    )

    expect(approvals.stats('project-1')).to have_attributes(
      approval_rate: nil, median_seconds_to_decision: nil, p90_seconds_to_decision: nil, functions: [], daily: []
    )
    expect(calls.first.last.fetch(:options)).to eq({})
  end

  it 'approves with a comment and returns the decided approval', :aggregate_failures do
    responses[:approve_durable_approval] = transport_response(200, decided('approved', 'ship it'))

    result = approvals.approve('project-1', 'approval-1', comment: 'ship it')

    expect(result).to have_attributes(status: 'approved')
    expect(result.decision).to have_attributes(comment: 'ship it', decided_at: Time.utc(2026, 10, 6, 12, 5))
    expect(result.decision.decided_by).to eq(
      Volcano::DurableApprovalDecider.new(id: 'user-1', email: 'ops@example.com')
    )
    expect(calls).to eq(
      [[:approve_durable_approval, {
        authorization: 'platform-token', project_id: 'project-1', approval_id: 'approval-1', comment: 'ship it'
      }]]
    )
  end

  it 'denies without a comment' do
    responses[:deny_durable_approval] = transport_response(200, decided('denied', ''))

    expect(approvals.deny('project-1', 'approval-1')).to have_attributes(status: 'denied')
    expect(calls.first).to eq(
      [:deny_durable_approval, {
        authorization: 'platform-token', project_id: 'project-1', approval_id: 'approval-1', comment: nil
      }]
    )
  end

  it 'returns an approval unchanged when the same decision repeats' do
    responses[:approve_durable_approval] = transport_response(200, decided('approved', 'ship it'))

    first = approvals.approve('project-1', 'approval-1', comment: 'ship it')

    expect(approvals.approve('project-1', 'approval-1')).to eq(first)
  end

  it 'raises a permission error when a project access token decides' do
    responses[:approve_durable_approval] = transport_response(
      403, 'error' => 'project access tokens cannot decide durable approvals; ' \
                      'a person decides in the dashboard or with a platform token'
    )

    expect { approvals.approve('project-1', 'approval-1') }
      .to raise_error(Volcano::Error::PermissionDeniedError, /cannot decide durable approvals/) do |error|
        expect(error).to be_a(Volcano::Error::AuthenticationError)
        expect(error).to have_attributes(status: 403, code: nil)
      end
  end

  %w[approval_decided approval_expired approval_cancelled].each do |code|
    it "raises a conflict for #{code}" do
      responses[:deny_durable_approval] = transport_response(409, 'error' => 'approval is closed', 'code' => code)

      expect { approvals.deny('project-1', 'approval-1') }
        .to raise_error(Volcano::Error::ConflictError, 'approval is closed') do |error|
          expect(error).to have_attributes(status: 409, code: code)
        end
    end
  end

  it 'raises for an approval that does not exist' do
    responses[:get_durable_approval] = transport_response(404, 'error' => 'durable approval not found')

    expect { approvals.get('project-1', 'approval-1') }
      .to raise_error(Volcano::Error::NotFoundError, 'durable approval not found') do |error|
        expect(error).to have_attributes(status: 404)
      end
  end

  it 'requires a platform credential' do
    public_client = described_class.new(anon_key: 'anon-key', service_key: 'service-key', _transport: transport)

    expect { public_client.durable.approvals.list('project-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect { public_client.durable.approvals.deny('project-1', 'approval-1') }
      .to raise_error(Volcano::Error::AuthenticationError, 'No active session')
    expect(calls).to be_empty
  end

  it 'rejects blank path segments before transport', :aggregate_failures do
    ['', '  ', nil].each do |blank|
      expect { approvals.list(blank) }.to raise_error(ArgumentError, /project_id/)
      expect { approvals.get('project-1', blank) }.to raise_error(ArgumentError, /approval_id/)
      expect { approvals.stats(blank) }.to raise_error(ArgumentError, /project_id/)
      expect { approvals.approve('project-1', blank) }.to raise_error(ArgumentError, /approval_id/)
      expect { approvals.deny(blank, 'approval-1') }.to raise_error(ArgumentError, /project_id/)
    end
    expect(calls).to be_empty
  end

  # The generated client checks these bounds itself and answers with its own
  # vocabulary; the caller reads a message about what they passed instead.
  it 'refuses filters and comments the API would not accept', :aggregate_failures do
    expect { approvals.list('project-1', function: '') }.to raise_error(ArgumentError, /function must be/)
    expect { approvals.stats('project-1', function: 'f' * 256) }.to raise_error(ArgumentError, /function must be/)
    expect { approvals.list('project-1', function: 12) }.to raise_error(ArgumentError, /function must be/)
    expect { approvals.list('project-1', execution_id: ' ') }.to raise_error(ArgumentError, /execution_id/)
    expect { approvals.list('project-1', status: '') }.to raise_error(ArgumentError, /status/)
    expect { approvals.list('project-1', limit: 101) }.to raise_error(ArgumentError, /limit must be/)
    expect { approvals.list('project-1', page: 0) }.to raise_error(ArgumentError, /page must be/)
    expect { approvals.approve('project-1', 'approval-1', comment: 'c' * 2001) }
      .to raise_error(ArgumentError, /comment must be a String of at most 2000 characters/)
    expect { approvals.deny('project-1', 'approval-1', comment: 7) }.to raise_error(ArgumentError, /comment/)
    expect(calls).to be_empty
  end

  it 'refuses a filter it does not know, as an unknown keyword', :aggregate_failures do
    expect { approvals.list('project-1', state: 'pending') }.to raise_error(ArgumentError, 'unknown keywords: state')
    expect { approvals.list('project-1', { status: 'pending', fn: 'x' }) }
      .to raise_error(ArgumentError, 'unknown keywords: fn')
    expect { approvals.list('project-1', 'pending') }.to raise_error(TypeError, 'filters must be a Hash')
    expect(calls).to be_empty
  end

  it 'accepts a comment at the length limit' do
    responses[:approve_durable_approval] = transport_response(200, decided('approved', ''))

    approvals.approve('project-1', 'approval-1', comment: 'é' * 2000)

    expect(calls.first.last.fetch(:comment)).to eq('é' * 2000)
  end

  [12, 'yesterday', '2026-13-01T00:00:00Z'].each do |value|
    it "refuses a window bound of #{value.inspect}" do
      expect { approvals.list('project-1', from: value) }
        .to raise_error(ArgumentError, 'from must be a Time or an ISO 8601 timestamp')
      expect { approvals.stats('project-1', to: value) }
        .to raise_error(ArgumentError, 'to must be a Time or an ISO 8601 timestamp')
    end
  end
end
