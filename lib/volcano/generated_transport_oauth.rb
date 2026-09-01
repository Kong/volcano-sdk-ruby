# frozen_string_literal: true

module Volcano
  # OAuth operations for the internal generated transport.
  class GeneratedTransport
    def auth_list_oauth_providers(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.auth_list_o_auth_providers_with_http_info)
      end
    end
  end
end
