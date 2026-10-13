# frozen_string_literal: true

require 'time'

module Volcano
  # Builds durable messages and message pages from transport payloads.
  module DurableMessageResponses
    INCOMPLETE_MESSAGE = 'Expected a complete durable message'
    INCOMPLETE_PAGE = 'Expected a complete durable message page'
    DIRECTIONS = %w[in out].freeze
    STATUSES = %w[queued delivering delivered dropped published].freeze
    private_constant :INCOMPLETE_MESSAGE, :INCOMPLETE_PAGE, :DIRECTIONS, :STATUSES

    private

    def durable_message(payload)
      values = message_object(payload, INCOMPLETE_MESSAGE)
      id, execution_id, name = message_labels(values)
      direction, status = message_states(values)
      DurableMessage.new(
        id: id, execution_id: execution_id, direction: direction, seq: message_seq(values['seq']), name: name,
        data: message_data(values['data']), sender: message_sender(values['sender']), status: status,
        sent_at: message_time(values['sent_at']), delivered_at: optional_message_time(values['delivered_at'])
      )
    end

    def message_labels(values)
      [message_text(values['id']), message_text(values['execution_id']), message_text(values['name'])]
    end

    def message_states(values)
      [message_choice(values['direction'], DIRECTIONS), message_choice(values['status'], STATUSES)]
    end

    def durable_message_page(payload)
      values = message_object(payload, INCOMPLETE_PAGE)
      data = values['data']
      raise TypeError, INCOMPLETE_PAGE unless data.is_a?(Array)

      messages = data.map { |entry| durable_message(entry) }
      DurableMessagePage.new(messages: messages, has_more: page_flag(values['has_more']))
    end

    def page_flag(value)
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

      raise TypeError, INCOMPLETE_PAGE
    end

    def message_object(payload, message)
      raise TypeError, message unless payload.is_a?(Hash)

      payload
    end

    def message_text(value)
      raise TypeError, INCOMPLETE_MESSAGE unless value.is_a?(String) && !value.empty?

      value
    end

    def message_choice(value, choices)
      choices.find { |choice| choice == value } || raise(TypeError, INCOMPLETE_MESSAGE)
    end

    def message_seq(value)
      raise TypeError, INCOMPLETE_MESSAGE unless value.is_a?(Integer) && value.positive?

      value
    end

    def message_data(value)
      Transport.json_value(value)
    rescue TypeError
      raise TypeError, INCOMPLETE_MESSAGE, cause: nil
    end

    def message_sender(payload)
      values = message_object(payload, INCOMPLETE_MESSAGE)
      user_id = values['user_id']
      raise TypeError, INCOMPLETE_MESSAGE unless user_id.nil? || user_id.is_a?(String)

      DurableMessageSender.new(type: message_text(values['type']), user_id: user_id)
    end

    def message_time(value)
      raise TypeError, INCOMPLETE_MESSAGE unless value.is_a?(String)

      Time.iso8601(value)
    rescue ArgumentError
      raise TypeError, INCOMPLETE_MESSAGE, cause: nil
    end

    def optional_message_time(value)
      value.nil? ? nil : message_time(value)
    end
  end
  private_constant :DurableMessageResponses
end
