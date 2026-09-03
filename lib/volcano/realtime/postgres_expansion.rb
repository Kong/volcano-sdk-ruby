# frozen_string_literal: true

module Volcano
  class Realtime
    # Expands lightweight Postgres identities into callback-ready changes.
    module PostgresExpansion
      private

      def expanded_postgres_change(request)
        change = request.change
        return delete_postgres_change(change) if lightweight_delete?(change)
        return change unless request.database_name && request.access_token

        fetch_postgres_change(request)
      rescue Error::VolcanoError, KeyError, TypeError => e
        report_postgres_fetch_error(request, e)
        change
      end

      def lightweight_delete?(change)
        change.mode == 'lightweight' && change.type == 'DELETE'
      end

      def fetch_postgres_change(request)
        change = request.change
        row = @realtime.__send__(
          :fetch_postgres_row, change, request.database_name, request.access_token
        )
        raise Error::NotFoundError, 'Postgres row not found' unless row

        change.with(record: row, id: nil, mode: nil)
      end

      def report_postgres_fetch_error(request, error)
        @realtime.__send__(:report_channel_error, error) if current_postgres_request?(request)
      end

      def delete_postgres_change(change)
        old_record = change.old_record || (change.id && { 'id' => change.id })
        change.with(old_record:, id: nil, mode: nil)
      end
    end
    private_constant :PostgresExpansion
  end
end
