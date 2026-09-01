# frozen_string_literal: true

module Volcano
  # Session-management operations for the internal generated transport.
  class GeneratedTransport
    def auth_delete_all_my_sessions(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.authentication.auth_delete_all_my_sessions_with_http_info)
      end
    end

    def auth_delete_my_session(authorization:, session_id:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.authentication.auth_delete_my_session_with_http_info(session_id))
      end
    end
  end
end
