# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Implements account conversion, confirmation, recovery, and email changes.
  module AuthAccount
    def sign_up_anonymous(user_metadata: nil)
      commit_session { mapping(anonymous_body(:auth_signup_anonymous, 201, user_metadata:)) }
    end

    def convert_anonymous(email:, password:, user_metadata: nil)
      synchronize_auth_operation do
        payload = authenticated_body(
          :auth_convert_anonymous, 200, secrets: [password], email:, password:, user_metadata:
        )
        converted_user = build_payload_user(payload)
        begin
          refresh_session
        rescue Error::VolcanoError
          nil
        end
        @client.current_user || converted_user
      end
    end

    def confirm_email(token:)
      payload = anonymous_body(:auth_confirm_email, 200, secrets: [token], token:)
      result = build_message(mapping(payload))
      refresh_user_best_effort if @client.current_session
      result
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
      synchronize_auth_operation do
        payload = anonymous_body(
          :auth_reset_password, 200, secrets: [token, new_password], token:, new_password:
        )
        build_message(mapping(payload)).tap { validate_session_after_password_reset }
      end
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
      synchronize_auth_operation do
        payload = authenticated_body(
          :auth_confirm_email_change, 200, secrets: [token], email_change_token: token
        )
        response = mapping(payload)
        update_user_after_email_change(response)
        build_message(response)
      end
    end

    def cancel_email_change
      build_message(mapping(authenticated_body(:auth_cancel_email_change, 200)))
    end

    private

    def validate_session_after_password_reset
      synchronize_auth_operation do
        session = @client.current_session
        return unless session

        begin
          fetch_user
        rescue Error::VolcanoError
          @client.clear_auth if @client.current_session.equal?(session)
        end
      end
    end

    def store_payload_user(payload)
      user = build_payload_user(payload)
      @client.store_user(user)
      user
    rescue KeyError
      raise auth_response_error
    end

    def update_user_after_email_change(payload)
      return store_payload_user(payload) if payload.key?('user')

      @client.clear_user
      refresh_user_best_effort
    end

    def build_payload_user(payload)
      build_user(mapping(mapping(payload).fetch('user')))
    rescue KeyError
      raise auth_response_error
    end

    def refresh_user_best_effort
      get_user
    rescue Error::VolcanoError
      nil
    end
  end
  private_constant :AuthAccount
end
