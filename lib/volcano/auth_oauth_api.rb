# frozen_string_literal: true

module Volcano
  # Fixed-host OAuth-provider API proxy behavior for the auth facade.
  class Auth
    def call_oauth_api(provider, endpoint:, method: 'GET', body: nil)
      session_payload(200, decode: :oauth_api_data) do
        provider_name = oauth_provider_name(provider)
        request = { endpoint: endpoint.dup.freeze, method: method.dup.freeze,
                    body: body.nil? ? nil : JSON.parse(JSON.generate(body), freeze: true) }
        ->(token) { oauth_api_response(token, provider_name, **request) }
      end
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
      when Hash then freeze_oauth_api_data_hash(value)
      when Array
        value.map { |item| freeze_oauth_api_data(item) }.freeze
      when String
        value.dup.freeze
      else
        freeze_oauth_api_data_scalar(value)
      end
    end

    def freeze_oauth_api_data_scalar(value)
      value.frozen? ? value : value.dup.freeze
    end

    def freeze_oauth_api_data_hash(value)
      value.to_h { |key, item| [freeze_oauth_api_data(key), freeze_oauth_api_data(item)] }.freeze
    end
  end
end
