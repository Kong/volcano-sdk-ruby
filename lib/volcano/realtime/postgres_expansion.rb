# frozen_string_literal: true

module Volcano
  class Realtime
    # Expands lightweight Postgres identities into callback-ready changes.
    module PostgresExpansion
      # @dynamic current_postgres_request?, postgres_batch_key

      private

      def expanded_postgres_changes(requests)
        return local_postgres_changes(requests) unless requests.first.database_name

        records = fetch_postgres_records(requests)
        requests.map { |request| expanded_postgres_record(request, records) }
      rescue Error::VolcanoError, KeyError, TypeError => e
        report_postgres_fetch_error(requests.first, e)
        requests.map(&:change)
      end

      def local_postgres_changes(requests)
        requests.map { |request| local_postgres_change(request.change) }
      end

      def lightweight_delete?(change)
        change.mode == 'lightweight' && change.type == 'DELETE'
      end

      def fetch_postgres_records(requests)
        request = requests.first
        database_name = request.database_name
        lineage = request.session_lineage
        raise TypeError, 'invalid Postgres fetch request' unless database_name && lineage.is_a?(SessionOperations)

        access_token = @realtime.__send__(
          :access_token_for_protocol_lineage, lineage
        )
        rows = @realtime.__send__(
          :fetch_postgres_rows, request.change, postgres_ids(requests),
          database_name, access_token
        )
        rows.to_h { |row| [row.fetch('id').to_s, row] }
      end

      def postgres_ids(requests)
        requests.to_h { |request| [request.change.id.to_s, request.change.id] }.values
      end

      def expanded_postgres_record(request, records)
        record = records.fetch(request.change.id.to_s, nil)
        unless record
          report_postgres_fetch_error(request, Error::NotFoundError.new('Postgres row not found'))
          return request.change
        end

        request.change.with(record: record, id: nil, mode: nil)
      end

      def report_postgres_fetch_error(request, error)
        @realtime.__send__(:report_channel_error, error) if current_postgres_request?(request)
      end

      def delete_postgres_change(change)
        old_record = change.old_record || (change.id ? { 'id' => change.id } : nil)
        change.with(old_record:, id: nil, mode: nil)
      end

      def local_postgres_change(change)
        return delete_postgres_change(change) if lightweight_delete?(change)

        change
      end
    end
    private_constant :PostgresExpansion
  end
end
