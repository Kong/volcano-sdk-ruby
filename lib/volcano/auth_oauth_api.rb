# frozen_string_literal: true

module Volcano
  # Fixed-host OAuth-provider API proxy behavior for the auth facade.
  class Auth
    def call_oauth_api(provider, endpoint:, method: 'GET', body: nil)
      provider_name = oauth_provider_name(provider)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      response = oauth_api_response(
        current.access_token, provider_name, endpoint: endpoint, method: method, body: body
      )
      result = oauth_api_data(Transport.body(response, 200))
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      result
    end

    private

    def oauth_api_response(access_token, provider, endpoint:, method:, body:)
      Transport.invoke do
        @transport.auth_call_oauth_api(
          authorization: access_token, provider: provider, endpoint: endpoint,
          method: method, body: body
        )
      end
    end

    def oauth_api_data(response_body)
      data = response_body.fetch('data')
      freeze_oauth_api_data(data)
    rescue KeyError, NoMethodError
      raise TypeError, 'Expected OAuth provider API response data'
    end

    def freeze_oauth_api_data(value)
      case value
      when Hash
        value.to_h { |key, item| [freeze_oauth_api_data(key), freeze_oauth_api_data(item)] }.freeze
      when Array
        value.map { |item| freeze_oauth_api_data(item) }.freeze
      when String
        value.dup.freeze
      else
        value.frozen? ? value : value.dup.freeze
      end
    end
  end
end
