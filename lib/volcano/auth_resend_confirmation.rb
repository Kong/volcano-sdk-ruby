# frozen_string_literal: true

module Volcano
  # Enumeration-safe confirmation resend behavior for the auth facade.
  class Auth
    def resend_confirmation(email:)
      Transport.body(resend_confirmation_response(email:), 200)
      nil
    end

    private

    def resend_confirmation_response(email:)
      Transport.invoke do
        @transport.auth_resend_confirmation(authorization: @client.anon_token, email:)
      end
    end
  end
end
