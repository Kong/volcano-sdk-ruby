# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Implements account conversion, confirmation, recovery, and email changes.
  module AuthAccount
    def sign_up_anonymous(user_metadata: nil)
      payload = anonymous_body(:auth_signup_anonymous, 201, user_metadata:)
      commit_session(mapping(payload))
    end

    def convert_anonymous(email:, password:, user_metadata: nil)
      payload = authenticated_body(
        :auth_convert_anonymous, 200, secrets: [password], email:, password:, user_metadata:
      )
      store_payload_user(payload)
    end

    def confirm_email(token:)
      payload = anonymous_body(:auth_confirm_email, 200, secrets: [token], token:)
      build_message(mapping(payload))
    end

    def resend_confirmation(email:)
      payload = anonymous_body(:auth_resend_confirmation, 200, email:)
      build_message(mapping(payload))
    end

    def forgot_password(email:)
      payload = anonymous_body(:auth_forgot_password, 200, email:)
      build_message(mapping(payload))
    end

    def reset_password(token:, new_password:)
      payload = anonymous_body(
        :auth_reset_password, 200, secrets: [token, new_password], token:, new_password:
      )
      result = build_message(mapping(payload))
      @client.clear_auth
      result
    end

    def request_email_change(new_email:)
      payload = mapping(authenticated_body(:auth_request_email_change, 200, new_email:))
      EmailChangeResult.new(
        message: payload.fetch('message'), new_email: payload.fetch('new_email'),
        email_change_token: payload['email_change_token']
      )
    rescue KeyError
      raise auth_response_error
    end

    def confirm_email_change(token:)
      payload = authenticated_body(
        :auth_confirm_email_change, 200, secrets: [token], email_change_token: token
      )
      response = mapping(payload)
      store_payload_user(response)
      build_message(response)
    end

    def cancel_email_change
      build_message(mapping(authenticated_body(:auth_cancel_email_change, 200)))
    end

    private

    def store_payload_user(payload)
      user = build_user(mapping(mapping(payload).fetch('user')))
      @client.store_user(user)
      user
    rescue KeyError
      raise auth_response_error
    end
  end
  private_constant :AuthAccount
end
