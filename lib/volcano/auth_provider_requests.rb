# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Retries provider API calls only for rejected Volcano sessions.
  module AuthProviderRequests
    private

    def provider_api_body(arguments)
      authenticated_body(
        :call_oauth_provider_api, 200, retry_unauthorized: false, **arguments
      )
    end

    def retry_provider_api_body(arguments)
      provider_api_body(arguments)
    rescue Error::AuthenticationError => e
      @client.clear_auth if AuthProviderErrors.session_failure?(e)
      raise
    end

    def recover_provider_api(arguments, error)
      raise error unless AuthProviderErrors.session_failure?(error)

      unless @client.current_session&.refresh_token
        @client.clear_auth
        raise error
      end
      refresh_session
      retry_provider_api_body(arguments)
    end
  end
  private_constant :AuthProviderRequests
end
