# frozen_string_literal: true

# Ruby SDK runtime and immutable database builders.
module Volcano
  QueryContext = Data.define(:client, :transport, :database_name)
  private_constant :QueryContext
  QueryState = Data.define(:columns, :filters, :order, :limit, :offset)
  private_constant :QueryState
  # @type var empty_columns: Array[String]
  empty_columns = []
  empty_columns.freeze
  # @type var empty_conditions: Array[query_condition]
  empty_conditions = []
  empty_conditions.freeze
  EMPTY_QUERY_STATE = QueryState.new(
    columns: empty_columns,
    filters: empty_conditions,
    order: empty_conditions,
    limit: nil,
    offset: nil
  )
  private_constant :EMPTY_QUERY_STATE

  # Adds the shared immutable filter vocabulary to database builders.
  module FilterMethods
    # @dynamic copy
    def eq(column, value) = add_filter(column, 'eq', value)
    def neq(column, value) = add_filter(column, 'neq', value)
    def gt(column, value) = add_filter(column, 'gt', value)
    def gte(column, value) = add_filter(column, 'gte', value)
    def lt(column, value) = add_filter(column, 'lt', value)
    def lte(column, value) = add_filter(column, 'lte', value)
    def like(column, pattern) = add_filter(column, 'like', pattern)
    def ilike(column, pattern) = add_filter(column, 'ilike', pattern)
    def is(column, value) = add_filter(column, 'is', value)
    def in(column, values) = add_filter(column, 'in', values)

    private

    def add_filter(column, operator, value)
      condition = {
        'column' => ImmutableRequestValue.capture(column),
        'operator' => operator,
        'value' => ImmutableRequestValue.capture(value)
      }.freeze
      copy(filters: [*@filters, condition])
    end
  end
  private_constant :FilterMethods

  # Creates immutable queries scoped to one project database.
  class Database
    def initialize(client, transport, name)
      database_name = ImmutableRequestValue.capture(name)
      @context = QueryContext.new(client:, transport:, database_name:)
    end

    def from(table)
      QueryBuilder.new(@context, table)
    end
  end

  # Builds and executes immutable database select queries.
  class QueryBuilder
    include FilterMethods

    def initialize(context, table, state: EMPTY_QUERY_STATE)
      @context = context
      @table = ImmutableRequestValue.capture(table)
      @columns = state.columns
      @filters = state.filters
      @order = state.order
      @limit = state.limit
      @offset = state.offset
      freeze
    end

    def select(*columns)
      copy(columns: ImmutableRequestValue.capture(columns))
    end

    def insert(values) = InsertBuilder.new(@context, @table, ImmutableRequestValue.capture(values))

    def update(values)
      UpdateBuilder.new(@context, @table, ImmutableRequestValue.capture(values), filters: @filters)
    end

    def delete
      DeleteBuilder.new(@context, @table, filters: @filters)
    end

    def order(column, ascending: true)
      clause = { 'column' => ImmutableRequestValue.capture(column), 'ascending' => ascending }.freeze
      copy(order: [*@order, clause])
    end

    def limit(count)
      copy(limit: count)
    end

    def offset(count)
      copy(offset: count)
    end

    def execute
      response = @context.client.session_request do |token|
        Transport.invoke do
          @context.transport.query_database_select(
            authorization: token,
            database_name: @context.database_name,
            body: query_body
          )
        end
      end
      Transport.json_rows(Transport.body(response, 200))
    end

    private

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
      # @type var body: sdk_payload
      body = { 'table' => @table }
      body.tap do |body|
        add_query_selection(body)
        body['limit'] = @limit unless @limit.nil?
        body['offset'] = @offset unless @offset.nil?
      end
    end

    def add_query_selection(body)
      body.tap do
        body['select'] = @columns unless @columns.empty? || @columns == ['*']
        body['filters'] = @filters unless @filters.empty?
        body['order'] = @order unless @order.empty?
      end
    end
  end

  # Builds and executes an immutable database insert.
  class InsertBuilder
    def initialize(context, table, values)
      @context = context
      @table = table
      @values = values
      freeze
    end

    def execute
      response = @context.client.session_request do |token|
        Transport.invoke do
          @context.transport.query_database_insert(
            authorization: token,
            database_name: @context.database_name,
            body: { 'table' => @table, 'values' => @values }
          )
        end
      end
      Transport.json_rows(Transport.body(response, 200))
    end
  end

  # Builds and executes an immutable filtered database update.
  class UpdateBuilder
    include FilterMethods

    def initialize(context, table, values, filters: EMPTY_QUERY_STATE.filters)
      @context = context
      @table = table
      @values = values
      @filters = filters
      freeze
    end

    def execute
      response = @context.client.session_request do |token|
        Transport.invoke do
          @context.transport.query_database_update(
            authorization: token,
            database_name: @context.database_name,
            body: { 'table' => @table, 'values' => @values, 'filters' => @filters }
          )
        end
      end
      Transport.json_rows(Transport.body(response, 200))
    end

    private

    def copy(filters:)
      self.class.new(@context, @table, @values, filters: filters.freeze)
    end
  end

  # Builds and executes an immutable filtered database delete.
  class DeleteBuilder
    include FilterMethods

    def initialize(context, table, filters: EMPTY_QUERY_STATE.filters)
      @context = context
      @table = table
      @filters = filters
      freeze
    end

    def execute
      response = @context.client.session_request do |token|
        Transport.invoke do
          @context.transport.query_database_delete(
            authorization: token,
            database_name: @context.database_name,
            body: { 'table' => @table, 'filters' => @filters }
          )
        end
      end
      Transport.json_rows(Transport.body(response, 200))
    end

    private

    def copy(filters:)
      self.class.new(@context, @table, filters: filters.freeze)
    end
  end
end
