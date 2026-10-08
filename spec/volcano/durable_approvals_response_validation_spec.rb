# frozen_string_literal: true

RSpec.describe Volcano::DurableApprovals do
  let(:transport) { instance_double(Volcano.const_get(:GeneratedTransport)) }
  let(:client) { Volcano::Client.new(anon_key: 'anon', access_token: 'access', _transport: transport) }
  let(:approvals) { client.durable.approvals }
  let(:empty_page) { { 'data' => [], 'page' => 1, 'limit' => 20, 'total' => 0, 'has_more' => false } }

  def approval
    {
      'id' => 'approval', 'status' => 'pending', 'name' => 'ship', 'title' => 'Ship?', 'description' => '',
      'function' => { 'id' => 'function', 'name' => 'pipeline' },
      'execution' => { 'id' => 'execution', 'name' => 'run', 'status' => 'running' },
      'requested_at' => '2026-10-06T12:00:00Z', 'expires_at' => nil, 'decision' => nil
    }
  end

  def self.counts
    { 'requested' => 1, 'pending' => 1, 'approved' => 0, 'denied' => 0, 'expired' => 0, 'cancelled' => 0 }
  end

  def self.stats
    {
      'from' => '2026-09-06T00:00:00Z', 'to' => '2026-10-06T00:00:00Z', 'counts' => counts,
      'approval_rate' => nil, 'median_seconds_to_decision' => nil, 'p90_seconds_to_decision' => nil,
      'functions' => [{ 'function' => { 'id' => nil, 'name' => 'pipeline' }, 'counts' => counts }],
      'other_functions' => counts, 'daily' => [{ 'date' => '2026-10-06', 'counts' => counts }]
    }
  end

  def response(payload)
    Volcano::Transport::Response.new(status: 200, body: payload, headers: {}, data: nil)
  end

  def self.decision(**fields)
    { 'comment' => '', 'decided_by' => { 'id' => 'user', 'email' => 'ops@example.com' },
      'decided_at' => '2026-10-06T12:01:00Z' }.merge(fields.transform_keys(&:to_s))
  end

  [nil, [], 'invalid', {}].each do |payload|
    it "rejects a malformed approval payload #{payload.inspect}" do
      allow(transport).to receive(:get_durable_approval).and_return(response(payload))

      expect { approvals.get('project', 'approval') }.to raise_error(TypeError, 'Expected a complete durable approval')
    end
  end

  [
    { 'id' => nil }, { 'status' => ' ' }, { 'name' => 12 }, { 'title' => nil }, { 'description' => nil },
    { 'details' => Object.new }, { 'details' => { status: 'done' } }, { 'function' => nil },
    { 'function' => { 'id' => 12, 'name' => 'pipeline' } }, { 'function' => { 'id' => nil, 'name' => '' } },
    { 'execution' => 'run' }, { 'execution' => { 'id' => nil, 'name' => nil, 'status' => nil } },
    { 'execution' => { 'id' => nil, 'name' => 'run', 'status' => 5 } }, { 'requested_at' => nil },
    { 'requested_at' => 'yesterday' }, { 'requested_at' => 12 }, { 'expires_at' => 12 }, { 'decision' => 'approved' },
    { 'decision' => decision(comment: nil) }, { 'decision' => decision(decided_by: 'user') },
    { 'decision' => decision(decided_by: { 'id' => 'user' }) },
    { 'decision' => decision(decided_by: { 'id' => '', 'email' => 'ops@example.com' }) },
    { 'decision' => decision(decided_by: { 'id' => 'user', 'email' => 7 }) },
    { 'decision' => decision(decided_at: nil) }
  ].each do |fields|
    it "rejects malformed approval fields #{fields.inspect}" do
      allow(transport).to receive(:get_durable_approval).and_return(response(approval.merge(fields)))

      expect { approvals.get('project', 'approval') }.to raise_error(TypeError, 'Expected a complete durable approval')
    end
  end

  it 'preserves timestamp objects in an approval response' do
    timestamp = Time.utc(2026)
    decided = self.class.decision(decided_at: timestamp)
    allow(transport).to receive(:get_durable_approval)
      .and_return(response(approval.merge('requested_at' => timestamp, 'decision' => decided)))

    expect(approvals.get('project', 'approval')).to have_attributes(requested_at: timestamp)
  end

  [nil, [], 'invalid', {}].each do |payload|
    it "rejects a malformed approval page #{payload.inspect}" do
      allow(transport).to receive(:list_durable_approvals).and_return(response(payload))

      expect { approvals.list('project') }.to raise_error(TypeError, 'Expected a complete durable approval page')
    end
  end

  [{ 'data' => nil }, { 'data' => {} }, { 'has_more' => 'yes' }, { 'page' => nil },
   { 'limit' => '20' }, { 'total' => 1.5 }].each do |fields|
    it "rejects a page with #{fields.inspect}" do
      allow(transport).to receive(:list_durable_approvals).and_return(response(empty_page.merge(fields)))

      expect { approvals.list('project') }.to raise_error(TypeError, 'Expected a complete durable approval page')
    end
  end

  it 'rejects a page whose entries are not approvals' do
    allow(transport).to receive(:list_durable_approvals).and_return(response(empty_page.merge('data' => [nil])))

    expect { approvals.list('project') }.to raise_error(TypeError, 'Expected a complete durable approval')
  end

  [
    nil, stats.merge('from' => nil), stats.merge('to' => 'later'), stats.merge('counts' => nil),
    stats.merge('counts' => counts.merge('requested' => '1')), stats.merge('counts' => counts.except('cancelled')),
    stats.merge('approval_rate' => '0.5'), stats.merge('median_seconds_to_decision' => true),
    stats.merge('functions' => nil), stats.merge('functions' => [nil]),
    stats.merge('functions' => [{ 'function' => nil, 'counts' => counts }]),
    stats.merge('functions' => [{ 'function' => { 'id' => nil, 'name' => 'pipeline' }, 'counts' => [] }]),
    stats.merge('other_functions' => nil), stats.merge('daily' => {}), stats.merge('daily' => ['2026-10-06']),
    stats.merge('daily' => [{ 'date' => '2026-10-6', 'counts' => counts }]),
    stats.merge('daily' => [{ 'date' => '2026-13-01', 'counts' => counts }]),
    stats.merge('daily' => [{ 'date' => '2026-02-30', 'counts' => counts }]),
    stats.merge('daily' => [{ 'date' => nil, 'counts' => counts }])
  ].each do |payload|
    it "rejects malformed statistics #{payload.inspect}" do
      allow(transport).to receive(:get_durable_approval_stats).and_return(response(payload))

      expect { approvals.stats('project') }
        .to raise_error(TypeError, 'Expected complete durable approval statistics')
    end
  end

  it 'converts whole-second decision times to floats' do
    allow(transport).to receive(:get_durable_approval_stats)
      .and_return(response(self.class.stats.merge('approval_rate' => 1, 'p90_seconds_to_decision' => 7)))

    expect(approvals.stats('project')).to have_attributes(approval_rate: 1.0, p90_seconds_to_decision: 7.0)
  end
end
