# frozen_string_literal: true

module Volcano
  class Database
    def initialize(client, name)
      @client = client
      @name = name
    end

    def from(table)
      QueryBuilder.new(@client, @name, table)
    end
  end

  class QueryBuilder
    def initialize(client, database_name, table, columns: [], filters: [])
      @client = client
      @database_name = database_name
      @table = table
      @columns = columns.freeze
      @filters = filters.freeze
      freeze
    end

    def select(*columns)
      self.class.new(
        @client,
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
        @client.transport.query_database_select(
          authorization: @client.session_token,
          database_name: @database_name,
          body: body
        )
      end
      Transport.body(response, 200).fetch('data')
    end
  end
end
