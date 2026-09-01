# frozen_string_literal: true

module Volcano
  # Email-token confirmation behavior for the authentication facade.
  class Auth
    def confirm_email(token:)
      Transport.body(confirm_email_response(token:), 200)
      nil
    end

    private

    def confirm_email_response(token:)
      Transport.invoke do
        @transport.auth_confirm_email(authorization: @client.anon_token, token:)
      end
    end
  end
end
