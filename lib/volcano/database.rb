# frozen_string_literal: true

module Volcano
  QueryContext = Data.define(:client, :transport, :database_name)
  private_constant :QueryContext
  QueryState = Data.define(:columns, :filters, :order, :limit, :offset)
  private_constant :QueryState
  EMPTY_QUERY_STATE = QueryState.new(
    columns: [].freeze,
    filters: [].freeze,
    order: [].freeze,
    limit: nil,
    offset: nil
  )
  private_constant :EMPTY_QUERY_STATE

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
    def initialize(context, table, state: EMPTY_QUERY_STATE)
      @context = context
      @table = table
      @columns = state.columns
      @filters = state.filters
      @order = state.order
      @limit = state.limit
      @offset = state.offset
      freeze
    end

    def select(*columns)
      copy(columns:)
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

    def order(column, ascending: true)
      clause = { 'column' => column, 'ascending' => ascending }.freeze
      copy(order: [*@order, clause])
    end

    def limit(count)
      copy(limit: count)
    end

    def offset(count)
      copy(offset: count)
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
      copy(filters: [*@filters, condition])
    end

    def copy(
      columns: @columns,
      filters: @filters,
      order: @order,
      limit: @limit,
      offset: @offset
    )
      self.class.new(
        @context,
        @table,
        state: QueryState.new(
          columns: columns.freeze,
          filters: filters.freeze,
          order: order.freeze,
          limit:,
          offset:
        )
      )
    end

    def query_body
      { 'table' => @table }.tap do |body|
        body['select'] = @columns unless @columns.empty? || @columns == ['*']
        body['filters'] = @filters unless @filters.empty?
        body['order'] = @order unless @order.empty?
        body['limit'] = @limit unless @limit.nil?
        body['offset'] = @offset unless @offset.nil?
      end
    end
  end
end
