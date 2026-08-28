# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Validates and maps session-less signup acknowledgements.
  module AuthSignupMapping
    private

    def signup_result(payload)
      confirmation_required = payload.fetch('confirmation_required')
      message = payload.fetch('message')
      validate_signup_acknowledgement(confirmation_required, message)
      SignUpResult.new(confirmation_required:, message:)
    rescue KeyError
      raise auth_response_error
    end

    def validate_signup_acknowledgement(confirmation_required, message)
      valid = [true, false].include?(confirmation_required) && message.is_a?(String)
      raise auth_response_error unless valid
    end
  end
  private_constant :AuthSignupMapping
end
