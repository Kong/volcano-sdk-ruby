# frozen_string_literal: true

module Volcano
  # Email-token confirmation behavior for the authentication facade.
  class Auth
    INVALID_CONFIRM_EMAIL_RESULT = 'Expected a valid email confirmation acknowledgement'
    private_constant :INVALID_CONFIRM_EMAIL_RESULT

    def confirm_email(token:)
      build_confirm_email_result(Transport.body(confirm_email_response(token:), 200))
    end

    private

    def confirm_email_response(token:)
      Transport.invoke do
        @transport.auth_confirm_email(authorization: @client.anon_token, token:)
      end
    end

    def build_confirm_email_result(payload)
      raise TypeError, INVALID_CONFIRM_EMAIL_RESULT unless payload.is_a?(Hash)

      ConfirmEmailResult.new(
        message: confirm_email_field(payload['message']),
        redirect_to: confirm_email_field(payload['redirect_to'])
      )
    end

    def confirm_email_field(value)
      return if value.nil?
      raise TypeError, INVALID_CONFIRM_EMAIL_RESULT unless value.is_a?(String)

      value.dup.freeze
    end
  end
end
