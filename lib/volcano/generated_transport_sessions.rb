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
  end
end
