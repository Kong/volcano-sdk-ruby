# frozen_string_literal: true

require 'volcano'

requested = Time.utc(2026, 10, 1)
function = Volcano::DurableApprovalFunction.new(id: nil, name: 'refunds')
raise 'Wrong function' unless function.id.nil? && function.name == 'refunds'
raise 'Wrong positional function' unless Volcano::DurableApprovalFunction['function', 'refunds'].id == 'function'
raise 'Wrong function keys' unless function.deconstruct_keys([:name])[:name] == 'refunds'

execution = Volcano::DurableApprovalExecution.new(id: 'execution', name: 'refund-42', status: 'running')
raise 'Wrong execution' unless execution.with(id: nil, status: nil).name == 'refund-42'

decider = Volcano::DurableApprovalDecider.new('user', 'ops@example.com')
decision = Volcano::DurableApprovalDecision.new(comment: 'ok', decided_by: decider, decided_at: requested)
raise 'Wrong decision' unless decision.decided_by&.email == 'ops@example.com'
raise 'Wrong deleted decider' unless decision.with(decided_by: nil).decided_by.nil?

approval = Volcano::DurableApproval.new(
  id: 'approval', status: 'approved', name: 'refund', title: 'Refund order 42', description: '',
  details: { 'amount' => 42 }, function: function, execution: execution, requested_at: requested,
  decision: decision
)
raise 'Wrong approval' unless approval.decision == decision && approval.expires_at.nil?
raise 'Wrong approval members' unless Volcano::DurableApproval.members.first == :id
raise 'Wrong approval tuple' unless approval.deconstruct[1] == 'approved'

page = Volcano::DurableApprovalPage.new(approvals: [approval], page: 1, limit: 20, total: 1, has_more: false)
raise 'Wrong page' unless page.approvals == [approval] && !page.has_more
raise 'Wrong positional page' unless Volcano::DurableApprovalPage[[approval], 1, 20, 1, false] == page

counts = Volcano::DurableApprovalCounts.new(
  requested: 3, pending: 1, approved: 1, denied: 1, expired: 0, cancelled: 0
)
by_function = Volcano::DurableApprovalFunctionCounts.new(function: function, counts: counts)
daily = Volcano::DurableApprovalDailyCounts.new(date: '2026-10-01', counts: counts)
stats = Volcano::DurableApprovalStats.new(
  from: requested, to: requested + 86_400, counts: counts, approval_rate: 0.5,
  functions: [by_function], other_functions: counts.with(requested: 0, pending: 0, approved: 0, denied: 0),
  daily: [daily]
)
raise 'Wrong stats' unless stats.approval_rate&.to_s == '0.5' && stats.median_seconds_to_decision.nil?
raise 'Wrong stats day' unless stats.daily.first&.date == '2026-10-01'
raise 'Wrong stats snapshot' unless stats.to_h[:functions] == [by_function]
