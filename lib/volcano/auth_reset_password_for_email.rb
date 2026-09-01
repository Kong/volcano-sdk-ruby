# frozen_string_literal: true

module Volcano
  # Password-reset request behavior for the authentication facade.
  class Auth
    def reset_password_for_email(email:)
      Transport.body(reset_password_for_email_response(email:), 200)
      nil
    end

    private

    def reset_password_for_email_response(email:)
      Transport.invoke do
        @transport.auth_forgot_password(authorization: @client.anon_token, email: email)
      end
    end
  end
end
