# frozen_string_literal: true

module Volcano
  # Server-held OAuth-provider token metadata behavior for the auth facade.
  class Auth
    def get_oauth_provider_token(provider)
      session_payload(200, decode: :oauth_provider_token_status) do
        provider_name = oauth_provider_name(provider)
        ->(token) { oauth_provider_token_response(token, provider_name) }
      end
    end

    def refresh_oauth_provider_token(provider)
      session_payload(200, decode: :oauth_provider_token_status) do
        provider_name = oauth_provider_name(provider)
        ->(token) { refresh_oauth_provider_token_response(token, provider_name) }
      end
    end

    private

    def oauth_provider_token_response(access_token, provider)
      Transport.invoke do
        @transport.auth_get_oauth_provider_token(authorization: access_token, provider: provider)
      end
    end

    def refresh_oauth_provider_token_response(access_token, provider)
      Transport.invoke do
        @transport.auth_refresh_oauth_provider_token(authorization: access_token, provider: provider)
      end
    end

    def oauth_provider_token_status(body)
      message, provider, expires_in = body.fetch_values('message', 'provider', 'expires_in')
      OAuthProviderTokenStatus.new(message:, provider:, expires_in:)
    rescue KeyError, NoMethodError
      raise TypeError, 'Expected complete OAuth provider token status'
    end
  end
end
