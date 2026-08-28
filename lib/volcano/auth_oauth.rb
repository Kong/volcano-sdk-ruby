# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  PROVIDER_NOT_LINKED_CODE = 'provider_not_linked'

  # Implements hosted auth, OAuth provider, and device-session operations.
  module AuthOAuth
    def get_hosted_auth_url(project_id:, action: nil)
      state = SecureRandom.urlsafe_base64(32)
      query = { anon_key: @client.anon_token, state: }
      query[:action] = action if action
      project = URI.encode_www_form_component(project_id)
      url = "#{@client.api_url}/projects/#{project}/auth/hosted?#{URI.encode_www_form(query)}"
      AuthorizationRequest.new(authorization_url: url, state:)
    end

    def get_oauth_authorization_url(provider:, redirect_url:)
      provider = validate_provider(provider)
      state = SecureRandom.urlsafe_base64(32)
      response = securely(@client.anon_token, state) do
        oauth_authorization_response(provider, redirect_url, state)
      end
      AuthorizationRequest.new(authorization_url: response_header(response, 'Location'), state:)
    end

    def exchange_oauth_code(code:, redirect_url:, state:, expected_state:)
      raise Error::ValidationError, 'OAuth state mismatch' unless secure_state?(state, expected_state)

      payload = anonymous_body(
        :auth_oauth_exchange, 200, secrets: [code, state, expected_state], code:, redirect_url:
      )
      commit_session(mapping(payload))
    end

    def link_oauth_provider(provider:, redirect_url:)
      state = SecureRandom.urlsafe_base64(32)
      payload = mapping(authenticated_body(
                          :auth_link_oauth_provider, 200, secrets: [state],
                                                          provider: validate_provider(provider),
                                                          redirect_url:, state:
                        ))
      AuthorizationRequest.new(authorization_url: payload.fetch('authorization_url'), state:)
    rescue KeyError
      raise auth_response_error
    end

    def unlink_oauth_provider(provider:)
      authenticated_body(:auth_unlink_oauth_provider, 204, provider: validate_provider(provider))
      nil
    end

    def linked_oauth_providers
      payload = mapping(authenticated_body(:auth_list_oauth_providers, 200))
      array(payload.fetch('providers')).map { |provider| build_oauth_provider(provider) }.freeze
    rescue KeyError, TypeError
      raise auth_response_error
    end
    alias get_linked_oauth_providers linked_oauth_providers
    private :linked_oauth_providers

    def refresh_oauth_token(provider:)
      payload = authenticated_body(
        :refresh_oauth_provider_token, 200, provider: validate_provider(provider)
      )
      build_oauth_token(mapping(payload))
    end

    def get_oauth_provider_token(provider:)
      payload = authenticated_body(
        :get_oauth_provider_token, 200, provider: validate_provider(provider)
      )
      build_oauth_token(mapping(payload))
    end

    def call_oauth_api(provider:, endpoint:, method: 'GET', body: nil)
      synchronize_auth_operation do
        arguments = { provider: validate_provider(provider), endpoint:, method:, body: }
        provider_api_body(arguments)
      rescue Error::AuthenticationError => e
        raise unless refresh_provider_request?(e)

        refresh_session
        retry_provider_api_body(arguments)
      end
    end

    private

    def provider_api_body(arguments)
      authenticated_body(
        :call_oauth_provider_api, 200, retry_unauthorized: false, **arguments
      )
    end

    def retry_provider_api_body(arguments)
      provider_api_body(arguments)
    rescue Error::AuthenticationError => e
      @client.clear_auth if refresh_provider_request?(e)
      raise
    end

    def refresh_provider_request?(error)
      session = @client.current_session
      error.status == 401 && session&.refresh_token && error.code != PROVIDER_NOT_LINKED_CODE
    end

    def build_oauth_provider(provider)
      value = mapping(provider)
      OAuthProvider.new(
        provider: validate_provider(value.fetch('provider')),
        linked_at: optional_time(value['linked_at']),
        updated_at: optional_time(value['updated_at'])
      )
    end

    def oauth_authorization_response(provider, redirect_url, state)
      response = transport_response(
        :auth_oauth_authorize, authorization: @client.anon_token,
                               provider:, redirect_url:, state:
      )
      Transport.body(response, 307)
      response
    end
  end
  private_constant :PROVIDER_NOT_LINKED_CODE
  private_constant :AuthOAuth
end
