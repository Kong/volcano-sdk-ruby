# frozen_string_literal: true

module Volcano
  # Email confirmation operations for the internal generated transport.
  class GeneratedTransport
    def auth_confirm_email(authorization:, token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthConfirmEmailRequest.new(token:)
        data, status, headers = apis.authentication.auth_confirm_email_with_http_info(
          request, debug_return_type: 'String'
        )
        response(data, status, headers)
      end
    end

    def auth_resend_confirmation(authorization:, email:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthForgotPasswordRequest.new(email:)
        data, status, headers = apis.authentication.auth_resend_confirmation_with_http_info(
          request, debug_return_type: 'String'
        )
        response(data, status, headers)
      end
    end
  end
end
