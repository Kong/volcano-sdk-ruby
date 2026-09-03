# frozen_string_literal: true

module Volcano
  class Realtime
    # Expands lightweight Postgres identities into callback-ready changes.
    module PostgresExpansion
      private

      def expanded_postgres_changes(requests)
        return requests.map { |request| local_postgres_change(request.change) } unless requests.first.database_name

        records = fetch_postgres_records(requests)
        requests.map { |request| expanded_postgres_record(request, records) }
      rescue Error::VolcanoError, KeyError, TypeError => e
        report_postgres_fetch_error(requests.first, e)
        requests.map(&:change)
      end

      def lightweight_delete?(change)
        change.mode == 'lightweight' && change.type == 'DELETE'
      end

      def fetch_postgres_records(requests)
        request = requests.first
        access_token = @realtime.__send__(
          :access_token_for_protocol_lineage, request.session_lineage
        )
        rows = @realtime.__send__(
          :fetch_postgres_rows, request.change, postgres_ids(requests),
          request.database_name, access_token
        )
        rows.to_h { |row| [row.fetch('id').to_s, row] }
      end

      def postgres_ids(requests)
        requests.to_h { |request| [request.change.id.to_s, request.change.id] }.values
      end

      def expanded_postgres_record(request, records)
        record = records[request.change.id.to_s]
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
        old_record = change.old_record || (change.id && { 'id' => change.id })
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
