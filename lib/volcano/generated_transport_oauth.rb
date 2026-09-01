# frozen_string_literal: true

module Volcano
  # OAuth operations for the internal generated transport.
  class GeneratedTransport
    def auth_oauth_authorization_url(anon_key:, provider:, redirect_url:, client_state:)
      oauth_authorization_api.auth_o_auth_authorize_with_http_info(
        provider, anon_key,
        redirect_url:, client_state:, response_mode: 'code'
      ).first
    end

    def auth_oauth_exchange(authorization:, code:, redirect_url:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthOAuthExchangeRequest.new(code:, redirect_url:)
        response(*apis.oauth.auth_o_auth_exchange_with_http_info(request))
      end
    end

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

    def auth_get_oauth_provider_token(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.get_o_auth_provider_token_with_http_info(provider))
      end
    end

    def auth_refresh_oauth_provider_token(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.oauth.refresh_o_auth_provider_token_with_http_info(provider))
      end
    end

    def auth_call_oauth_api(authorization:, provider:, endpoint:, method:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::CallOAuthProviderAPIRequest.new(endpoint:, method:, body:)
        response(*apis.oauth.call_o_auth_provider_api_with_http_info(provider, request))
      end
    end
  end
end
