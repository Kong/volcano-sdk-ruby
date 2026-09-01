# frozen_string_literal: true

module Volcano
  # OAuth operations for the internal generated transport.
  class GeneratedTransport
    def auth_link_oauth_provider(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.auth_link_o_auth_provider_with_http_info(provider))
      end
    end

    def auth_list_oauth_providers(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.auth_list_o_auth_providers_with_http_info)
      end
    end

    def auth_unlink_oauth_provider(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.auth_unlink_o_auth_provider_with_http_info(provider))
      end
    end
  end
end
