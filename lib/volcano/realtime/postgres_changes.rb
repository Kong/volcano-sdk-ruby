# frozen_string_literal: true

module Volcano
  class Realtime
    PostgresChange = Data.define(
      :type, :schema, :table, :record, :old_record, :columns, :timestamp, :id, :mode
    ) do
      def initialize(
        type:, schema:, table:, timestamp:, record: nil, old_record: nil, columns: nil,
        id: nil, mode: nil
      )
        super(
          type: Immutable.call(type.to_s), schema: Immutable.call(schema.to_s),
          table: Immutable.call(table.to_s), record: record && Immutable.call(record),
          old_record: old_record && Immutable.call(old_record),
          columns: columns && Immutable.call(columns), timestamp: Immutable.call(timestamp.to_s),
          id: id && Immutable.call(id), mode: mode && Immutable.call(mode.to_s)
        )
      end
    end

    # Registers filtered callbacks for Postgres change publications.
    module PostgresChanges
      CHANGE_EVENTS = %w[INSERT UPDATE DELETE].freeze
      EVENTS = [*CHANGE_EVENTS, '*'].freeze

      def on_postgres_changes(event, schema:, table:, callback: nil, &block)
        ensure_postgres!
        event = event.to_s.upcase
        raise ArgumentError, "unsupported postgres change event: #{event}" unless EVENTS.include?(event)

        handler = callback || block || raise(ArgumentError, 'callback or block is required')
        on(event) do |change|
          handler.call(change) if change.schema == schema.to_s && change.table == table.to_s
        end
      end

      private

      def dispatch_postgres_change(data)
        change = postgres_change(data)
        return unless change

        emit(change.type, change)
        emit('*', change)
      end

      def postgres_change(data)
        return unless valid_postgres_change?(data)

        PostgresChange.new(
          type: data.fetch('type'), schema: data.fetch('schema'), table: data.fetch('table'),
          record: data['record'], old_record: data['old_record'], columns: data['columns'],
          timestamp: data.fetch('timestamp'), id: data['id'], mode: data['mode']
        )
      end

      def valid_postgres_change?(data)
        valid_postgres_identity?(data) && valid_postgres_payload?(data)
      end

      def valid_postgres_identity?(data)
        data.is_a?(Hash) && CHANGE_EVENTS.include?(data['type']) &&
          data['schema'].is_a?(String) && data['table'].is_a?(String) &&
          data['timestamp'].is_a?(String)
      end

      def valid_postgres_payload?(data)
        optional_hash?(data['record']) && optional_hash?(data['old_record']) &&
          optional_array?(data['columns']) && [nil, 'lightweight'].include?(data['mode'])
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
