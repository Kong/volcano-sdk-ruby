# frozen_string_literal: true

module Volcano
  # Email-change operations for the internal generated transport.
  class GeneratedTransport
    INVALID_EMAIL_CHANGE_RESPONSE = 'Expected a valid email-change acknowledgement'
    private_constant :INVALID_EMAIL_CHANGE_RESPONSE

    def auth_request_email_change(authorization:, new_email:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRequestEmailChangeRequest.new(new_email:)
        data, status, headers = apis.authentication.auth_request_email_change_with_http_info(
          request,
          debug_return_type: 'String'
        )
        response(JSON.parse(data), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise TypeError, INVALID_EMAIL_CHANGE_RESPONSE, cause: e
    end

    def auth_cancel_email_change(authorization:)
      invoke do
        apis = @api_factory.call(authorization)
        response(*apis.authentication.auth_cancel_email_change_with_http_info)
      end
    end

    def auth_confirm_email_change(authorization:, token:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthConfirmEmailChangeRequest.new(email_change_token: token)
        body, status, headers = apis.authentication.auth_confirm_email_change_with_http_info(
          request,
          debug_return_type: 'String'
        )
        response(JSON.parse(body), status, headers)
      end
    rescue JSON::ParserError, TypeError => e
      raise Error::AuthenticationError, MALFORMED_USER_PROFILE, cause: e
    end
  end
end
