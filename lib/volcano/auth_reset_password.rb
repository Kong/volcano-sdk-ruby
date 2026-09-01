# frozen_string_literal: true

module Volcano
  # Recovery-token password reset behavior for the authentication facade.
  class Auth
    def reset_password(token:, new_password:)
      Transport.body(reset_password_response(token:, new_password:), 200)
      nil
    end

    private

    def reset_password_response(token:, new_password:)
      Transport.invoke do
        @transport.auth_reset_password(
          authorization: @client.anon_token,
          token: token,
          new_password: new_password
        )
      end
    end
  end
end
