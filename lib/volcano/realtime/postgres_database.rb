# frozen_string_literal: true

module Volcano
  class Realtime
    # Holds the database selection and performs token-bound row lookups.
    module PostgresDatabase
      DATABASE_NAME = /\A[a-z0-9_]{1,64}\z/
      FETCH_CONCURRENCY = 4
      private_constant :DATABASE_NAME, :FETCH_CONCURRENCY

      attr_reader :database_name

      def database_name=(name)
        unless name.nil? || (name.is_a?(String) && DATABASE_NAME.match?(name))
          raise ArgumentError,
                'database name must match ^[a-z0-9_]+$ and contain at most 64 characters'
        end
        @database_name = name&.dup&.freeze
      end

      private

      def initialize_postgres_database
        @database_name = nil
        @postgres_fetch_semaphore = nil
      end

      def capture_session = @client.capture_session
      def capture_session_binding = @client.capture_session_binding

      def capture_protocol_session
        generation, lineage, session = capture_session_binding
        return [generation, lineage, session] if session && session.user_id == @protocol_user_id

        raise Error::SessionChangedError
      end

      def fetch_postgres_row(change, database_name, access_token)
        table = change.schema == 'public' ? change.table : "#{change.schema}.#{change.table}"
        postgres_fetch_semaphore.acquire do
          BlockingCall.call do
            @client.__send__(:database_with_token, database_name, access_token)
                   .from(table).select('*').eq('id', change.id).limit(1).execute.first
          end
        end
      end

      def postgres_fetch_semaphore
        require 'async/semaphore'
        @postgres_fetch_semaphore ||= Async::Semaphore.new(FETCH_CONCURRENCY)
      end
    end
    private_constant :PostgresDatabase
  end
end
