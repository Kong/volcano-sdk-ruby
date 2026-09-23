# frozen_string_literal: true

Volcano::DurableExecutionError.new(type: 123)
Volcano::DurableExecution.new(
  id: 'execution', function_id: 'function', name: 'job', status: 'running',
  region: 'aws-us-east-1', created_at: 'today'
)
Volcano::DurableExecution.new(id: 'execution', function_id: 'function')
Volcano::DurableExecution['execution', 'function', 'job', 'running', 'aws-us-east-1', Time.now]
  .with(error: 'Failure')
Volcano::DurableExecutionPage.new(executions: ['not an execution'], page: 1, limit: 20, total: 1, has_more: false)
Volcano::DurableExecutionPage[
  [Volcano::DurableExecution.new('execution', 'function', 'job', 'running', 'aws-us-east-1', Time.now)],
  1, 20, 1, 'yes'
]
