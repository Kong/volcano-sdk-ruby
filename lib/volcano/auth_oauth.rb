# frozen_string_literal: true

module Volcano
  # Linked OAuth-provider behavior for the authentication facade.
  class Auth
    OAUTH_PROVIDERS = %w[apple github google microsoft].freeze
    private_constant :OAUTH_PROVIDERS

    def list_linked_oauth_providers
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      body = Transport.body(list_oauth_providers_response(current.access_token), 200)
      result = linked_oauth_providers(body)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    def link_oauth_provider(provider)
      provider_name = oauth_provider_name(provider)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      body = Transport.body(link_oauth_provider_response(current.access_token, provider_name), 200)
      result = oauth_authorization_url(body)
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    def unlink_oauth_provider(provider)
      provider_name = oauth_provider_name(provider)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      Transport.body(unlink_oauth_provider_response(current.access_token, provider_name), 204)
      raise Error::SessionChangedError unless @client.capture_session.first == generation
    end

    private

    def list_oauth_providers_response(access_token)
      Transport.invoke do
        @transport.auth_list_oauth_providers(authorization: access_token)
      end
    end

    def link_oauth_provider_response(access_token, provider)
      Transport.invoke do
        @transport.auth_link_oauth_provider(authorization: access_token, provider: provider)
      end
    end

    def unlink_oauth_provider_response(access_token, provider)
      Transport.invoke do
        @transport.auth_unlink_oauth_provider(authorization: access_token, provider: provider)
      end
    end

    def oauth_provider_name(provider)
      return provider if provider.is_a?(String) && OAUTH_PROVIDERS.include?(provider)

      raise ArgumentError, 'Unsupported OAuth provider'
    end

    def oauth_authorization_url(body)
      authorization_url = body.fetch('authorization_url') if body.is_a?(Hash)
      return authorization_url if authorization_url.is_a?(String) && !authorization_url.strip.empty?

      raise TypeError, 'Expected an OAuth authorization URL'
    rescue KeyError
      raise TypeError, 'Expected an OAuth authorization URL'
    end

    def linked_oauth_providers(body)
      raise TypeError, 'Expected complete linked OAuth providers' unless body.is_a?(Hash)

      providers = body.fetch('providers')
      raise TypeError, 'Expected complete linked OAuth providers' unless providers.is_a?(Array)

      providers.map { |attributes| linked_oauth_provider(attributes) }.freeze
    rescue KeyError
      raise TypeError, 'Expected complete linked OAuth providers'
    end

    def linked_oauth_provider(attributes)
      raise TypeError, 'Expected complete linked OAuth providers' unless attributes.is_a?(Hash)

      provider = attributes.fetch('provider')
      linked_at = attributes.fetch('linked_at')
      updated_at = attributes.fetch('updated_at')
      valid = provider.is_a?(String) && !provider.strip.empty? &&
              linked_at.is_a?(Time) && updated_at.is_a?(Time)
      raise TypeError, 'Expected complete linked OAuth providers' unless valid

      LinkedOAuthProvider.new(provider:, linked_at:, updated_at:)
    rescue KeyError
      raise TypeError, 'Expected complete linked OAuth providers'
    end
  end
end
