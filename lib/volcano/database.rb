# frozen_string_literal: true

module Volcano
  class Database
    def initialize(client, transport, name)
      @client = client
      @transport = transport
      @name = name
    end

    def from(table)
      QueryBuilder.new(@client, @transport, @name, table)
    end
  end

  class QueryBuilder
    def initialize(client, transport, database_name, table, columns: [], filters: [])
      @client = client
      @transport = transport
      @database_name = database_name
      @table = table
      @columns = columns.freeze
      @filters = filters.freeze
      freeze
    end

    def select(*columns)
      self.class.new(
        @client,
        @transport,
        @database_name,
        @table,
        columns: columns,
        filters: @filters
      )
    end

    def eq(column, value)
      condition = { 'column' => column, 'operator' => 'eq', 'value' => value }.freeze
      self.class.new(
        @client,
        @transport,
        @database_name,
        @table,
        columns: @columns,
        filters: [*@filters, condition]
      )
    end

    def execute
      body = { 'table' => @table }
      body['select'] = @columns unless @columns.empty? || @columns == ['*']
      body['filters'] = @filters unless @filters.empty?
      response = Transport.invoke do
        @transport.query_database_select(
          authorization: @client.session_token,
          database_name: @database_name,
          body: body
        )
      end
      Transport.body(response, 200).fetch('data')
    end
  end
end
