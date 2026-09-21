# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeDatabaseTransport
      def query_database_select(**arguments)
        @calls << [:query_database_select, arguments]
        Volcano::Transport::Response.new(status: 200, body: { 'data' => [{ 'slug' => 'a' }] }, headers: {}, data: nil)
      end

      def query_database_insert(**arguments)
        @calls << [:query_database_insert, arguments]
        values = arguments.fetch(:body).fetch('values')
        Volcano::Transport::Response.new(status: 200, body: { 'data' => [values] }, headers: {}, data: nil)
      end

      def query_database_update(**arguments)
        @calls << [:query_database_update, arguments]
        values = arguments.fetch(:body).fetch('values')
        Volcano::Transport::Response.new(status: 200, body: { 'data' => [values] }, headers: {}, data: nil)
      end

      def query_database_delete(**arguments)
        @calls << [:query_database_delete, arguments]
        Volcano::Transport::Response.new(status: 200, body: { 'data' => [{ 'id' => 'item-1' }] }, headers: {},
                                         data: nil)
      end
    end

    # Implements the storage operations used by the facade test transport.
  end
end
