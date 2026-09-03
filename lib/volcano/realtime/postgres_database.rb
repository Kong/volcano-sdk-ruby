# frozen_string_literal: true

module Volcano
  class Realtime
    # Holds the database selection and performs token-bound row lookups.
    module PostgresDatabase
      attr_reader :database_name

      def database_name=(name)
        @database_name = name&.dup&.freeze
      end

      private

      def initialize_postgres_database
        @database_name = nil
      end

      def capture_session = @client.capture_session

      def fetch_postgres_row(change, database_name, access_token)
        table = change.schema == 'public' ? change.table : "#{change.schema}.#{change.table}"
        @client.__send__(:database_with_token, database_name, access_token)
               .from(table).select('*').eq('id', change.id).limit(1).execute.first
      end
    end
    private_constant :PostgresDatabase
  end
end
