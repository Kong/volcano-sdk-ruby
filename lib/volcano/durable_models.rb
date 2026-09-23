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
  DurableExecutionError = Data.define(:type, :message)

  # Reopens the generated record for checked initialization.
  class DurableExecutionError
    # @dynamic type, message, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(type: nil, message: nil)
      type = type&.dup&.freeze
      message = message&.dup&.freeze
      super
    end
  end

  # A durable execution, as the platform last observed it.
  #
  # `result` is absent while the execution is still running, and absent again
  # once its retention lapses. That is not the same as a function that returned
  # nothing, so read `result_expired` before concluding anything from a missing
  # result.
  DurableExecution = Data.define(*DURABLE_EXECUTION_ATTRIBUTES)

  # Reopens the generated record for checked initialization.
  class DurableExecution
    # @dynamic id, function_id, name, status, region, created_at, result, result_expired
    # @dynamic error, completed_at, members, with, to_h, deconstruct, deconstruct_keys
    # @dynamic self.[], self.members
    def initialize(**attributes)
      unknown = attributes.keys - DURABLE_EXECUTION_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = DURABLE_EXECUTION_ATTRIBUTES.first(6) - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = DURABLE_EXECUTION_ATTRIBUTES.to_h do |name|
        [name, immutable_value(attributes[name])]
      end
      attributes = values
      super
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
  DurableExecutionPage = Data.define(:executions, :page, :limit, :total, :has_more)

  # Reopens the generated record for checked initialization.
  class DurableExecutionPage
    # @dynamic executions, page, limit, total, has_more, members, with, to_h
    # @dynamic deconstruct, deconstruct_keys, self.[], self.members
    def initialize(executions:, page:, limit:, total:, has_more:)
      executions = executions.to_a.dup.freeze
      super
    end
  end

  # Builds the public durable types from transport payloads.
  module DurableResponses
    INCOMPLETE_EXECUTION = 'Expected a complete durable execution'
    INCOMPLETE_PAGE = 'Expected a complete durable execution page'
    private_constant :INCOMPLETE_EXECUTION, :INCOMPLETE_PAGE

    private

    def durable_execution(payload)
      values = execution_payload(payload)
      DurableExecution.new(
        id: execution_text(values, 'id'), function_id: execution_text(values, 'function_id'),
        name: execution_text(values, 'name'), status: execution_text(values, 'status'),
        region: execution_text(values, 'region'), created_at: execution_time(values),
        result: execution_result(values['result']), result_expired: execution_expired(values['result_expired']),
        error: execution_error(values['error']), completed_at: parse_time(values['completed_at'])
      )
    end

    def execution_payload(payload)
      raise TypeError, INCOMPLETE_EXECUTION unless payload.is_a?(Hash)

      payload
    end

    def execution_text(values, field)
      value = values[field]
      raise TypeError, INCOMPLETE_EXECUTION unless value.is_a?(String) && !value.strip.empty?

      value
    end

    def execution_time(values)
      case (value = values['created_at'])
      when String then Time.iso8601(value)
      when Time then value
      else raise TypeError, INCOMPLETE_EXECUTION
      end
    end

    def execution_expired(value)
      return value if value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass)

      raise TypeError, INCOMPLETE_EXECUTION
    end

    def execution_result(value)
      Transport.json_value(value)
    rescue TypeError
      raise TypeError, INCOMPLETE_EXECUTION, cause: nil
    end

    def execution_error(payload)
      return if payload.nil?
      raise TypeError, INCOMPLETE_EXECUTION unless payload.is_a?(Hash)

      DurableExecutionError.new(type: payload['type'], message: payload['message'])
    end

    def durable_execution_page(payload)
      values, data, has_more = page_payload(payload)
      DurableExecutionPage.new(
        executions: data.map { |entry| durable_execution(entry) }, has_more: has_more,
        page: count(values['page']), limit: count(values['limit']), total: count(values['total'])
      )
    end

    def page_payload(payload)
      raise TypeError, INCOMPLETE_PAGE unless payload.is_a?(Hash)

      data = payload['data']
      has_more = payload['has_more']
      raise TypeError, INCOMPLETE_PAGE unless data.is_a?(Array) && [true, false].include?(has_more)

      [payload, data, has_more]
    end

    def count(value)
      raise TypeError, INCOMPLETE_PAGE unless value.is_a?(Integer)

      value
    end

    def present_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def parse_time(value)
      return Time.iso8601(value) if value.is_a?(String)
      return value if value.nil? || value.is_a?(Time)

      raise TypeError, INCOMPLETE_EXECUTION
    end
  end
  private_constant :DurableResponses
end
