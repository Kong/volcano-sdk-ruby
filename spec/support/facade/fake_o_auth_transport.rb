# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeOAuthTransport
      attr_accessor :link_oauth_provider_response, :list_oauth_providers_response,
                    :call_oauth_api_response,
                    :on_link_oauth_provider, :on_list_oauth_providers,
                    :on_call_oauth_api,
                    :oauth_provider_token_status_response,
                    :on_oauth_exchange, :on_oauth_provider_token_status,
                    :on_refresh_oauth_provider_token,
                    :on_unlink_oauth_provider, :refresh_oauth_provider_token_response

      def auth_oauth_authorization_url(**arguments)
        @calls << [:auth_oauth_authorization_url, arguments]
        'https://api.test.volcano.dev/auth/oauth/github/authorize?anon_key=anon-key'
      end

      def auth_oauth_exchange(**arguments)
        @calls << [:auth_oauth_exchange, arguments]
        @on_oauth_exchange&.call
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'access_token' => 'oauth-access', 'refresh_token' => 'oauth-refresh',
            'user' => { 'id' => 'oauth-user' }
          },
          headers: {}, data: nil
        )
      end

      def auth_list_oauth_providers(**arguments)
        @calls << [:auth_list_oauth_providers, arguments]
        @on_list_oauth_providers&.call
        @list_oauth_providers_response || Volcano::Transport::Response.new(
          status: 200,
          body: {
            'providers' => [
              {
                'provider' => 'google',
                'linked_at' => Time.iso8601('2026-08-30T12:00:00Z'),
                'updated_at' => Time.iso8601('2026-09-01T12:00:00Z')
              }
            ]
          },
          headers: {}, data: nil
        )
      end

      def auth_link_oauth_provider(**arguments)
        @calls << [:auth_link_oauth_provider, arguments]
        @on_link_oauth_provider&.call
        @link_oauth_provider_response || Volcano::Transport::Response.new(
          status: 200,
          body: { 'authorization_url' => 'https://accounts.example/link' },
          headers: {}, data: nil
        )
      end

      def auth_unlink_oauth_provider(**arguments)
        @calls << [:auth_unlink_oauth_provider, arguments]
        @on_unlink_oauth_provider&.call
        Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
      end

      def auth_get_oauth_provider_token(**arguments)
        @calls << [:auth_get_oauth_provider_token, arguments]
        @on_oauth_provider_token_status&.call
        @oauth_provider_token_status_response || Volcano::Transport::Response.new(
          status: 200,
          body: {
            'message' => 'Provider token is valid',
            'provider' => 'google',
            'expires_in' => 3600
          },
          headers: {}, data: nil
        )
      end

      def auth_refresh_oauth_provider_token(**arguments)
        @calls << [:auth_refresh_oauth_provider_token, arguments]
        @on_refresh_oauth_provider_token&.call
        @refresh_oauth_provider_token_response || Volcano::Transport::Response.new(
          status: 200,
          body: {
            'message' => 'Provider token refreshed successfully',
            'provider' => 'google',
            'expires_in' => 3600
          },
          headers: {}, data: nil
        )
      end

      def auth_call_oauth_api(**arguments)
        @calls << [:auth_call_oauth_api, arguments]
        @on_call_oauth_api&.call
        @call_oauth_api_response || Volcano::Transport::Response.new(
          status: 200,
          body: {
            'provider' => 'github',
            'endpoint' => '/user/repos',
            'status_code' => 200,
            'data' => [{ 'name' => 'volcano' }]
          },
          headers: {}, data: nil
        )
      end
    end
  end
end
