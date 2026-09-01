# frozen_string_literal: true

module Volcano
  # Current-user update behavior for the authentication facade.
  class Auth
    def update_user(password: nil, metadata: nil)
      generation, current = @client.capture_session
      raise Error::AuthenticationError, 'No active session' unless current

      payload = Transport.body(
        update_user_response(current.access_token, password:, metadata:),
        200
      )
      user = build_user(user_payload(payload))
      raise Error::SessionChangedError unless @client.capture_session.first == generation

      user
    end

    private

    def update_user_response(access_token, password:, metadata:)
      Transport.invoke do
        @transport.auth_update_user(
          authorization: access_token,
          password: password,
          metadata: metadata
        )
      end
    end
  end
end
