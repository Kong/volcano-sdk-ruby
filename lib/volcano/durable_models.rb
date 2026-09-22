# frozen_string_literal: true

require 'time'

module Volcano
  DURABLE_EXECUTION_ATTRIBUTES = %i[
    id function_id name status region created_at result result_expired error completed_at
  ].freeze
  private_constant :DURABLE_EXECUTION_ATTRIBUTES

  # `unknown` is terminal, and the platform writes it itself for an execution
  # whose outcome it could not determine. Code that switches on status has to
  # treat it as finished, or it reads a finished execution as still running.
  DURABLE_TERMINAL_STATUSES = %w[succeeded failed timed_out stopped unknown].freeze
  private_constant :DURABLE_TERMINAL_STATUSES

  # Why a failed or timed-out execution ended.
  DurableExecutionError = Data.define(:type, :message) do
    def initialize(type: nil, message: nil)
      super(type: type&.dup&.freeze, message: message&.dup&.freeze)
    end
  end

  # A durable execution, as the platform last observed it.
  #
  # `result` is absent while the execution is still running, and absent again
  # once its retention lapses. That is not the same as a function that returned
  # nothing, so read `result_expired` before concluding anything from a missing
  # result.
  DurableExecution = Data.define(*DURABLE_EXECUTION_ATTRIBUTES) do
    def initialize(**attributes)
      unknown = attributes.keys - DURABLE_EXECUTION_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = DURABLE_EXECUTION_ATTRIBUTES.first(6) - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = DURABLE_EXECUTION_ATTRIBUTES.to_h do |name|
        [name, immutable_value(attributes[name])]
      end
      super(**values)
    end

    # Reports whether the execution has stopped changing.
    def terminal?
      DURABLE_TERMINAL_STATUSES.include?(status)
    end

    private

    # `result` is the function's own JSON, so it is frozen all the way down.
    def immutable_value(value)
      case value
      when Hash then immutable_value_hash(value)
      when Array then value.map { |item| immutable_value(item) }.freeze
      when Time, String then value.dup.freeze
      else value
      end
    end

    def immutable_value_hash(value)
      value.to_h { |key, item| [immutable_value(key), immutable_value(item)] }.freeze
    end
  end

  # One page of a durable function's executions, most recent first.
  DurableExecutionPage = Data.define(:executions, :page, :limit, :total, :has_more) do
    def initialize(executions:, page:, limit:, total:, has_more:)
      super(
        executions: executions.to_a.dup.freeze,
        page: page, limit: limit, total: total, has_more: has_more
      )
    end
  end

  # Builds the public durable types from transport payloads.
  module DurableResponses
    INCOMPLETE_EXECUTION = 'Expected a complete durable execution'
    INCOMPLETE_PAGE = 'Expected a complete durable execution page'
    EXECUTION_FIELDS = %w[id function_id name status region].freeze
    private_constant :INCOMPLETE_EXECUTION, :INCOMPLETE_PAGE, :EXECUTION_FIELDS

    private

    def durable_execution(payload)
      values = execution_payload(payload)
      DurableExecution.new(
        id: values.fetch('id'), function_id: values.fetch('function_id'),
        name: values.fetch('name'), status: values.fetch('status'),
        region: values.fetch('region'), created_at: parse_time(values.fetch('created_at')),
        result: values['result'], result_expired: values['result_expired'],
        error: execution_error(values['error']), completed_at: parse_time(values['completed_at'])
      )
    end

    def execution_payload(payload)
      raise TypeError, INCOMPLETE_EXECUTION unless payload.is_a?(Hash)

      complete = EXECUTION_FIELDS.all? { |field| present_string?(payload[field]) }
      raise TypeError, INCOMPLETE_EXECUTION unless complete && payload['created_at']

      payload
    end

    def execution_error(payload)
      return if payload.nil?
      raise TypeError, INCOMPLETE_EXECUTION unless payload.is_a?(Hash)

      DurableExecutionError.new(type: payload['type'], message: payload['message'])
    end

    def durable_execution_page(payload)
      data, has_more = page_payload(payload)
      DurableExecutionPage.new(
        executions: data.map { |entry| durable_execution(entry) }, has_more: has_more,
        page: count(payload['page']), limit: count(payload['limit']), total: count(payload['total'])
      )
    end

    def page_payload(payload)
      raise TypeError, INCOMPLETE_PAGE unless payload.is_a?(Hash)

      data = payload['data']
      has_more = payload['has_more']
      raise TypeError, INCOMPLETE_PAGE unless data.is_a?(Array) && [true, false].include?(has_more)

      [data, has_more]
    end

    def count(value)
      raise TypeError, INCOMPLETE_PAGE unless value.is_a?(Integer)

      value
    end

    def present_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end
  end
  private_constant :DurableResponses
end
