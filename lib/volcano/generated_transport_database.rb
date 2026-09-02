# frozen_string_literal: true

module Volcano
  # Database operations for the internal generated transport.
  class GeneratedTransport
    def query_database_select(authorization:, database_name:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::DatabaseSelectRequest.new(deep_symbolize(body))
        data, status, headers = apis.database.query_database_select_with_http_info(
          database_name,
          request
        )
        response(data, status, headers)
      end
    end

    def query_database_insert(authorization:, database_name:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::DatabaseInsertRequest.new(deep_symbolize(body))
        data, status, headers = apis.database.query_database_insert_with_http_info(
          database_name,
          request
        )
        response(data, status, headers)
      end
    end

    def query_database_update(authorization:, database_name:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::DatabaseUpdateRequest.new(deep_symbolize(body))
        data, status, headers = apis.database.query_database_update_with_http_info(
          database_name,
          request
        )
        response(data, status, headers)
      end
    end
  end
end
