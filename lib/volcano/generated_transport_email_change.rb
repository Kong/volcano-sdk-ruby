# frozen_string_literal: true

module Volcano
  # Email-change operations for the internal generated transport.
  class GeneratedTransport
    def auth_request_email_change(authorization:, new_email:)
      invoke do
        apis = @api_factory.call(authorization)
        request = Generated::AuthRequestEmailChangeRequest.new(new_email:)
        data, status, headers = apis.authentication.auth_request_email_change_with_http_info(
          request,
          debug_return_type: 'String'
        )
        response(parse_body(data), status, headers)
      end
    end
  end
end
