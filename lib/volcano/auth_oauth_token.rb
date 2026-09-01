# frozen_string_literal: true

module Volcano
  # Server-held OAuth-provider token metadata behavior for the auth facade.
  class Auth
    def get_oauth_provider_token(provider)
      provider_name = oauth_provider_name(provider)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      body = Transport.body(oauth_provider_token_response(current.access_token, provider_name), 200)
      result = oauth_provider_token_status(body)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    private

    def oauth_provider_token_response(access_token, provider)
      Transport.invoke do
        @transport.auth_get_oauth_provider_token(authorization: access_token, provider: provider)
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
