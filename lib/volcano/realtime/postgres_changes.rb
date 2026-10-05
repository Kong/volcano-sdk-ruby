# frozen_string_literal: true

module Volcano
  class Realtime
    PostgresChange = Data.define(
      :type, :schema, :table, :record, :old_record, :columns, :timestamp, :id, :mode
    )

    # Immutable snapshot of a Postgres change publication.
    class PostgresChange
      def initialize(type:, schema:, table:, timestamp:, **payload)
        type = Immutable.call(type.to_s)
        schema = Immutable.call(schema.to_s)
        table = Immutable.call(table.to_s)
        timestamp = Immutable.call(timestamp.to_s)
        payload = snapshot_payload(payload)
        super
      end

      private

      def snapshot_payload(payload)
        payload = { record: nil, old_record: nil, columns: nil, id: nil, mode: nil }.merge(payload)
        %i[record old_record columns id].each { |field| payload[field] = Immutable.optional(payload[field]) }
        payload[:mode] &&= Immutable.call(payload[:mode].to_s)
        payload
      end
    end

    # Registers filtered callbacks for Postgres change publications.
    module PostgresChanges
      # @dynamic on, enqueue_postgres_delivery
      CHANGE_EVENTS = %w[INSERT UPDATE DELETE].freeze
      EVENTS = [*CHANGE_EVENTS, '*'].freeze

      def on_postgres_changes(event, schema:, table:, callback: nil, &block)
        ensure_postgres!
        event = postgres_event(event)
        handler = callback || block || raise(ArgumentError, 'callback or block is required')
        raise ArgumentError, 'callback must respond to call' unless handler.respond_to?(:call)

        register_postgres_listener(event, schema.to_s, table.to_s, handler)
      end

      private

      def dispatch_postgres_change(data)
        change = postgres_change(data)
        return unless change && postgres_listener?(change)

        enqueue_postgres_delivery(change)
      end

      def postgres_change(data)
        return unless data.is_a?(Hash) && valid_postgres_change?(data)

        PostgresChange.new(
          type: data.fetch('type'), schema: data.fetch('schema'), table: data.fetch('table'),
          record: data['record'], old_record: data['old_record'], columns: data['columns'],
          timestamp: data.fetch('timestamp'), id: data['id'], mode: data['mode']
        )
      end

      def postgres_event(event)
        event = event.to_s.upcase
        return event if EVENTS.include?(event)

        raise ArgumentError, "unsupported postgres change event: #{event}"
      end

      def register_postgres_listener(event, schema, table, handler)
        # @type var filtered: ^(Object?) -> void
        filtered = lambda do |change|
          handler.call(change) if change.is_a?(PostgresChange) && change.schema == schema && change.table == table
        end
        @postgres_filters[filtered] = [event, schema, table]
        on(event, filtered)
      end

      def postgres_listener?(change)
        callbacks = [*@callbacks[change.type], *@callbacks['*']]
        return true if callbacks.any? { |callback| !@postgres_filters.key?(callback) }

        @postgres_filters.any? do |callback, (event, schema, table)|
          callbacks.include?(callback) && postgres_filter_matches?(event, schema, table, change)
        end
      end

      def postgres_filter_matches?(event, schema, table, change)
        (event == '*' || event == change.type) && schema == change.schema && table == change.table
      end

      def valid_postgres_change?(data)
        data.is_a?(Hash) && valid_postgres_identity?(data) && valid_postgres_payload?(data)
      end

      def valid_postgres_identity?(data)
        data.is_a?(Hash) && CHANGE_EVENTS.include?(data['type']) &&
          data['schema'].is_a?(String) && data['table'].is_a?(String) &&
          data['timestamp'].is_a?(String)
      end

      def valid_postgres_payload?(data)
        mode = data['mode']
        optional_hash?(data['record']) && optional_hash?(data['old_record']) &&
          optional_array?(data['columns']) && (mode.nil? || mode == 'lightweight')
      end

      def optional_hash?(value) = value.nil? || value.is_a?(Hash)
      def optional_array?(value) = value.nil? || value.is_a?(Array)
      def broadcast? = @type == :broadcast
      def postgres? = @type == :postgres

      def ensure_postgres!
        return if postgres?

        raise ArgumentError, 'operation is only available for postgres channels'
      end
    end
    private_constant :PostgresChanges
  end
end
