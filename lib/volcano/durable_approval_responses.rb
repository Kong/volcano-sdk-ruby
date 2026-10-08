# frozen_string_literal: true

require 'time'

module Volcano
  # Checks the fields shared by approval and statistics payloads.
  module DurableApprovalFields
    INCOMPLETE_APPROVAL = 'Expected a complete durable approval'
    INCOMPLETE_PAGE = 'Expected a complete durable approval page'
    INCOMPLETE_STATS = 'Expected complete durable approval statistics'
    private_constant :INCOMPLETE_APPROVAL, :INCOMPLETE_PAGE, :INCOMPLETE_STATS

    private

    def approval_function(payload, message)
      values = approval_object(payload, message)
      DurableApprovalFunction.new(
        id: optional_approval_text(values['id'], message), name: approval_text(values['name'], message)
      )
    end

    def approval_object(payload, message)
      raise TypeError, message unless payload.is_a?(Hash)

      payload
    end

    def approval_list(value)
      raise TypeError, INCOMPLETE_STATS unless value.is_a?(Array)

      value
    end

    def approval_text(value, message = INCOMPLETE_APPROVAL)
      raise TypeError, message unless value.is_a?(String) && !value.strip.empty?

      value
    end

    def optional_approval_text(value, message)
      value.nil? ? nil : approval_text(value, message)
    end

    def approval_string(value, message)
      raise TypeError, message unless value.is_a?(String)

      value
    end

    def approval_time(value, message)
      case value
      when String then Time.iso8601(value)
      when Time then value
      else raise TypeError, message
      end
    rescue ArgumentError
      raise TypeError, message, cause: nil
    end

    def approval_count(value, message = INCOMPLETE_STATS)
      raise TypeError, message unless value.is_a?(Integer)

      value
    end

    def approval_flag(value)
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      raise TypeError, INCOMPLETE_PAGE
    end

    def approval_number(value)
      case value
      when nil then nil
      when Integer, Float then Float(value)
      else raise TypeError, INCOMPLETE_STATS
      end
    end
  end
  private_constant :DurableApprovalFields

  # Builds approvals and approval pages from transport payloads.
  module DurableApprovalResponses
    include DurableApprovalFields

    private

    def durable_approval(payload)
      values = approval_object(payload, INCOMPLETE_APPROVAL)
      id, status, name, title = approval_labels(values)
      requested_at, expires_at = approval_schedule(values)
      DurableApproval.new(
        id: id, status: status, name: name, title: title,
        description: approval_string(values['description'], INCOMPLETE_APPROVAL),
        details: approval_details(values['details']),
        function: approval_function(values['function'], INCOMPLETE_APPROVAL),
        execution: approval_execution(values['execution']), requested_at: requested_at, expires_at: expires_at,
        decision: approval_decision(values['decision'])
      )
    end

    def durable_approval_page(payload)
      values = approval_object(payload, INCOMPLETE_PAGE)
      data = values['data']
      raise TypeError, INCOMPLETE_PAGE unless data.is_a?(Array)

      DurableApprovalPage.new(
        approvals: data.map { |entry| durable_approval(entry) }, has_more: approval_flag(values['has_more']),
        page: approval_count(values['page'], INCOMPLETE_PAGE), limit: approval_count(values['limit'], INCOMPLETE_PAGE),
        total: approval_count(values['total'], INCOMPLETE_PAGE)
      )
    end

    def approval_labels(values)
      [approval_text(values['id']), approval_text(values['status']),
       approval_text(values['name']), approval_text(values['title'])]
    end

    def approval_schedule(values)
      expires_at = values['expires_at']
      [approval_time(values['requested_at'], INCOMPLETE_APPROVAL),
       expires_at.nil? ? nil : approval_time(expires_at, INCOMPLETE_APPROVAL)]
    end

    def approval_execution(payload)
      values = approval_object(payload, INCOMPLETE_APPROVAL)
      DurableApprovalExecution.new(
        id: optional_approval_text(values['id'], INCOMPLETE_APPROVAL), name: approval_text(values['name']),
        status: optional_approval_text(values['status'], INCOMPLETE_APPROVAL)
      )
    end

    def approval_decision(payload)
      return if payload.nil?

      values = approval_object(payload, INCOMPLETE_APPROVAL)
      DurableApprovalDecision.new(
        comment: approval_string(values['comment'], INCOMPLETE_APPROVAL),
        decided_by: approval_decider(values['decided_by']),
        decided_at: approval_time(values['decided_at'], INCOMPLETE_APPROVAL)
      )
    end

    def approval_decider(payload)
      return if payload.nil?

      values = approval_object(payload, INCOMPLETE_APPROVAL)
      DurableApprovalDecider.new(
        id: approval_text(values['id']), email: approval_string(values['email'], INCOMPLETE_APPROVAL)
      )
    end

    def approval_details(value)
      Transport.json_value(value)
    rescue TypeError
      raise TypeError, INCOMPLETE_APPROVAL, cause: nil
    end
  end
  private_constant :DurableApprovalResponses

  # Builds approval statistics from transport payloads.
  module DurableApprovalStatsResponses
    include DurableApprovalFields

    DAY = /\A\d{4}-\d{2}-\d{2}\z/
    private_constant :DAY

    private

    def durable_approval_stats(payload)
      values = approval_object(payload, INCOMPLETE_STATS)
      from, to = approval_window(values)
      rate, median, p90 = approval_timings(values)
      functions, daily = approval_breakdown(values)
      DurableApprovalStats.new(
        from: from, to: to, counts: approval_counts(values['counts']), approval_rate: rate,
        median_seconds_to_decision: median, p90_seconds_to_decision: p90, functions: functions,
        other_functions: approval_counts(values['other_functions']), daily: daily
      )
    end

    def approval_window(values)
      [approval_time(values['from'], INCOMPLETE_STATS), approval_time(values['to'], INCOMPLETE_STATS)]
    end

    def approval_timings(values)
      [approval_number(values['approval_rate']), approval_number(values['median_seconds_to_decision']),
       approval_number(values['p90_seconds_to_decision'])]
    end

    def approval_breakdown(values)
      [approval_list(values['functions']).map { |entry| approval_function_counts(entry) },
       approval_list(values['daily']).map { |entry| approval_daily_counts(entry) }]
    end

    def approval_counts(payload)
      values = approval_object(payload, INCOMPLETE_STATS)
      DurableApprovalCounts.new(
        requested: approval_count(values['requested']), pending: approval_count(values['pending']),
        approved: approval_count(values['approved']), denied: approval_count(values['denied']),
        expired: approval_count(values['expired']), cancelled: approval_count(values['cancelled'])
      )
    end

    def approval_function_counts(payload)
      values = approval_object(payload, INCOMPLETE_STATS)
      DurableApprovalFunctionCounts.new(
        function: approval_function(values['function'], INCOMPLETE_STATS), counts: approval_counts(values['counts'])
      )
    end

    def approval_daily_counts(payload)
      values = approval_object(payload, INCOMPLETE_STATS)
      date = approval_text(values['date'], INCOMPLETE_STATS)
      valid = DAY.match?(date) && approval_time("#{date}T00:00:00Z", INCOMPLETE_STATS).strftime('%F') == date
      raise TypeError, INCOMPLETE_STATS unless valid

      DurableApprovalDailyCounts.new(date: date, counts: approval_counts(values['counts']))
    end
  end
  private_constant :DurableApprovalStatsResponses
end
