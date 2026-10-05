# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeOAuthApi
      attr_reader :api_calls, :exchange_calls, :link_calls, :list_calls, :refresh_calls,
                  :token_status_calls, :unlink_calls

      def initialize
        @api_calls = []
        @exchange_calls = []
        @link_calls = []
        @list_calls = []
        @refresh_calls = []
        @token_status_calls = []
        @unlink_calls = []
      end

      def auth_o_auth_exchange_with_http_info(body)
        @exchange_calls << body
        result = {
          access_token: 'oauth-access', token_type: 'bearer', expires_in: 3600,
          refresh_token: 'oauth-refresh',
          user: { id: '00000000-0000-4000-8000-000000000010' }
        }
        [FakeGeneratedModel.new(result), 200, {}]
      end

      def auth_link_o_auth_provider_with_http_info(provider, options = {})
        @link_calls << [provider, options]
        result = { authorization_url: 'https://accounts.example/link' }
        [FakeGeneratedModel.new(result), 200, {}]
      end

      def auth_list_o_auth_providers_with_http_info(options = {})
        @list_calls << options
        providers = {
          providers: [
            {
              provider: 'google',
              linked_at: Time.iso8601('2026-08-30T12:00:00Z'),
              updated_at: Time.iso8601('2026-09-01T12:00:00Z')
            }
          ]
        }
        [FakeGeneratedModel.new(providers), 200, {}]
      end

      def auth_unlink_o_auth_provider_with_http_info(provider)
        @unlink_calls << provider
        [nil, 204, {}]
      end

      def get_o_auth_provider_token_with_http_info(provider)
        @token_status_calls << provider
        result = {
          message: 'Provider token is valid', provider: provider, expires_in: 3600
        }
        [FakeGeneratedModel.new(result), 200, {}]
      end

      def refresh_o_auth_provider_token_with_http_info(provider)
        @refresh_calls << provider
        result = {
          message: 'Provider token refreshed successfully', provider: provider, expires_in: 3600
        }
        [FakeGeneratedModel.new(result), 200, {}]
      end

      def call_o_auth_provider_api_with_http_info(provider, request)
        @api_calls << [provider, request]
        result = {
          provider: provider, endpoint: request.endpoint, status_code: 200,
          data: [{ name: 'volcano' }, nil]
        }
        [FakeGeneratedModel.new(result), 200, {}]
      end
    end
  end
end
