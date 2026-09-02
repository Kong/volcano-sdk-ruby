# frozen_string_literal: true

module Volcano
  QueryContext = Data.define(:client, :transport, :database_name)
  private_constant :QueryContext

  # Creates immutable queries scoped to one project database.
  class Database
    def initialize(client, transport, name)
      @context = QueryContext.new(client:, transport:, database_name: name)
    end

    def from(table)
      QueryBuilder.new(@context, table)
    end
  end

  # Builds and executes immutable database select queries.
  class QueryBuilder
    def initialize(context, table, columns: [], filters: [])
      @context = context
      @table = table
      @columns = columns.freeze
      @filters = filters.freeze
      freeze
    end

    def select(*columns)
      self.class.new(
        @context,
        @table,
        columns: columns,
        filters: @filters
      )
    end

    def eq(column, value)
      add_filter(column, 'eq', value)
    end

    def neq(column, value)
      add_filter(column, 'neq', value)
    end

    def gt(column, value)
      add_filter(column, 'gt', value)
    end

    def gte(column, value)
      add_filter(column, 'gte', value)
    end

    def lt(column, value)
      add_filter(column, 'lt', value)
    end

    def lte(column, value)
      add_filter(column, 'lte', value)
    end

    def execute
      response = Transport.invoke do
        @context.transport.query_database_select(
          authorization: @context.client.session_token,
          database_name: @context.database_name,
          body: query_body
        )
      end
      Transport.body(response, 200).fetch('data')
    end

    private

    def add_filter(column, operator, value)
      condition = { 'column' => column, 'operator' => operator, 'value' => value }.freeze
      self.class.new(
        @context,
        @table,
        columns: @columns,
        filters: [*@filters, condition]
      )
    end

    def query_body
      { 'table' => @table }.tap do |body|
        body['select'] = @columns unless @columns.empty? || @columns == ['*']
        body['filters'] = @filters unless @filters.empty?
      end
    end
  end
end
