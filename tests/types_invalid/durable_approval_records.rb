# frozen_string_literal: true

Volcano::DurableApprovalFunction.new(id: 1, name: 'refunds')
Volcano::DurableApprovalDecision.new(comment: 'ok', decided_by: 'user', decided_at: Time.now)
Volcano::DurableApproval.new(
  id: 'approval', status: 'pending', name: 'refund', title: 'Refund', description: '',
  function: Volcano::DurableApprovalFunction.new(id: nil, name: 'refunds'),
  execution: Volcano::DurableApprovalExecution.new(id: nil, name: 'refund-42', status: nil),
  requested_at: 'yesterday'
)
Volcano::DurableApprovalPage.new(approvals: ['approval'], page: 1, limit: 20, total: 1, has_more: false)
Volcano::DurableApprovalDailyCounts.new(date: Time.now, counts: nil)
