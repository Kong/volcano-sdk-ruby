# frozen_string_literal: true

require 'volcano'

created = Time.utc(2026, 9, 23)
failure = Volcano::DurableExecutionError.new(type: 'Failure', message: 'Failed')
raise 'Wrong error' unless failure.type == 'Failure'
raise 'Wrong positional error' unless Volcano::DurableExecutionError.new('Failure', 'Failed') == failure
raise 'Wrong error members' unless Volcano::DurableExecutionError.members == %i[type message]
raise 'Wrong updated error' unless failure.with(message: 'Changed').message == 'Changed'
raise 'Wrong error snapshot' unless failure.to_h[:message] == 'Failed'
raise 'Wrong error tuple' unless failure.deconstruct == %w[Failure Failed]
raise 'Wrong error keys' unless failure.deconstruct_keys([:type])[:type] == 'Failure'

mapped_error = failure.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped error' unless mapped_error['type'] == 'Failure'

execution = Volcano::DurableExecution.new(
  id: 'execution', function_id: 'function', name: 'job', status: 'running',
  region: 'aws-us-east-1', created_at: created
)
raise 'Wrong execution' unless execution.status == 'running' && !execution.terminal?
raise 'Wrong execution members' unless Volcano::DurableExecution.members == %i[
  id function_id name status region created_at result result_expired error completed_at
]

positional = Volcano::DurableExecution.new('execution', 'function', 'job', 'running', 'aws-us-east-1', created)
raise 'Wrong positional execution' unless positional == execution
raise 'Wrong bracket execution' unless Volcano::DurableExecution[
  'execution', 'function', 'job', 'running', 'aws-us-east-1', created
] == execution

updated = execution.with(status: 'failed', error: failure, result_expired: true)
raise 'Wrong terminal execution' unless updated.terminal? && updated.error == failure
raise 'Wrong execution snapshot' unless updated.to_h[:result_expired] == true
raise 'Wrong execution tuple' unless updated.deconstruct[3] == 'failed'
raise 'Wrong execution keys' unless updated.deconstruct_keys([:status])[:status] == 'failed'

mapped_execution = updated.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped execution' unless mapped_execution['status'] == 'failed'

page = Volcano::DurableExecutionPage.new(executions: [execution], page: 1, limit: 20, total: 1, has_more: false)
raise 'Wrong page' unless page.executions == [execution] && page.page == 1
raise 'Wrong page members' unless Volcano::DurableExecutionPage.members == %i[
  executions page limit total has_more
]
raise 'Wrong positional page' unless Volcano::DurableExecutionPage.new([execution], 1, 20, 1, false) == page
raise 'Wrong bracket page' unless Volcano::DurableExecutionPage[[execution], 1, 20, 1, false] == page

updated_page = page.with(page: 2, has_more: true)
raise 'Wrong page update' unless updated_page.page == 2 && updated_page.has_more
raise 'Wrong page snapshot' unless updated_page.to_h[:executions] == [execution]
raise 'Wrong page tuple' unless updated_page.deconstruct == [[execution], 2, 20, 1, true]
raise 'Wrong page keys' unless updated_page.deconstruct_keys([:page])[:page] == 2

mapped_page = updated_page.to_h { |name, value| [name.to_s, value.to_s] }
raise 'Wrong mapped page' unless mapped_page['page'] == '2'
