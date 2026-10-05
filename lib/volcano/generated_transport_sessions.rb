# frozen_string_literal: true

module Volcano
  # Session-management operations for the internal generated transport.
  class GeneratedTransport
    def auth_get_my_sessions(authorization:, page:, limit:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.authentication.auth_get_my_sessions_with_http_info(page: page, limit: limit)
        response(data, status, headers)
      end
    end

    def auth_delete_all_my_sessions(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.authentication.auth_delete_all_my_sessions_with_http_info
        response(data, status, headers)
      end
    end

    def auth_delete_my_session(authorization:, session_id:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.authentication.auth_delete_my_session_with_http_info(session_id)
        response(data, status, headers)
      end
    end
  end
end
