# frozen_string_literal: true

require 'date'

module Volcano
  # OAuth operations for the internal generated transport.
  class GeneratedTransport
    def auth_oauth_authorization_url(anon_key:, provider:, redirect_url:, client_state:)
      url = oauth_authorization_api.auth_o_auth_authorize_with_http_info(
        provider, anon_key,
        redirect_url:, client_state:, response_mode: 'code'
      ).first
      raise TypeError, 'Expected OAuth authorization URL' unless url.is_a?(String)

      url
    end

    def auth_oauth_exchange(authorization:, code:, redirect_url:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthOAuthExchangeRequest.new(code:, redirect_url:)
        data, status, headers = apis.oauth.auth_o_auth_exchange_with_http_info(request)
        response(data, status, headers)
      end
    end

    def auth_link_oauth_provider(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.oauth.auth_link_o_auth_provider_with_http_info(provider)
        response(data, status, headers)
      end
    end

    def auth_list_oauth_providers(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        body, status, headers = apis.oauth.auth_list_o_auth_providers_with_http_info(debug_return_type: 'String')
        response(linked_oauth_providers_body(body), status, headers)
      end
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError => e
      raise TypeError, 'Expected complete linked OAuth providers', cause: e
    end

    def auth_unlink_oauth_provider(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.oauth.auth_unlink_o_auth_provider_with_http_info(provider)
        response(data, status, headers)
      end
    end

    def auth_get_oauth_provider_token(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.oauth.get_o_auth_provider_token_with_http_info(provider)
        response(data, status, headers)
      end
    end

    def auth_refresh_oauth_provider_token(authorization:, provider:)
      invoke do
        apis = @api_factory.call(authorization)
        data, status, headers = apis.oauth.refresh_o_auth_provider_token_with_http_info(provider)
        response(data, status, headers)
      end
    end

    def auth_call_oauth_api(authorization:, provider:, endpoint:, method:, body:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::CallOAuthProviderAPIRequest.new(endpoint:, method:, body:)
        data, status, headers = apis.oauth.call_o_auth_provider_api_with_http_info(provider, request)
        response(data, status, headers)
      end
    end

    private

    # Provider IDs were added later; the stable facade still consumes three fields.
    def linked_oauth_providers_body(body)
      raise TypeError unless body.is_a?(String)

      payload = JSON.parse(body)
      raise TypeError unless payload.is_a?(Hash)

      providers = payload.fetch('providers')
      raise TypeError unless providers.is_a?(Array)

      payload.merge('providers' => providers.map { |item| linked_oauth_provider_body(item) })
    end

    def linked_oauth_provider_body(provider)
      raise TypeError unless provider.is_a?(Hash)

      provider.merge(
        'linked_at' => linked_oauth_provider_time(provider.fetch('linked_at')),
        'updated_at' => linked_oauth_provider_time(provider.fetch('updated_at'))
      )
    end

    def linked_oauth_provider_time(value)
      raise TypeError unless value.is_a?(String)
      raise TypeError unless value.match?(/\A
        \d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d
        (?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)
      \z/x)

      # Reject malformed offsets before DateTime can normalize them to UTC.
      DateTime.rfc3339(value, Date::GREGORIAN).to_time
    end
  end
end
