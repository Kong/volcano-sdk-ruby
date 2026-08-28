# frozen_string_literal: true

require_relative 'immutable_value'

module Volcano
  # Password rules enforced by the current project.
  PasswordPolicy = Data.define(
    :effective_min_length, :min_configurable_length, :max_length,
    :require_uppercase, :require_lowercase, :require_numbers,
    :require_special_chars, :compromised_passwords_rejected
  ) do
    def initialize(**attributes)
      super(**ImmutableValue.copy_attributes(**attributes))
    end
  end

  # RFC 8628 authorization details shown to a device user.
  DeviceAuthorization = Data.define(
    :device_code, :user_code, :verification_uri, :verification_uri_complete,
    :expires_in, :interval
  ) do
    include RedactedInspection

    def initialize(**attributes)
      super(**ImmutableValue.copy_attributes(**attributes))
    end

    def inspect
      "#<#{self.class} user_code=#{user_code.inspect} expires_in=#{expires_in.inspect}>"
    end
  end

  # Result of approving or denying a device authorization.
  DeviceVerification = Data.define(:success, :status) do
    def initialize(success: nil, status: nil)
      super(**ImmutableValue.copy_attributes(success:, status:))
    end
  end

  # Short-lived platform token issued for another client.
  PlatformToken = Data.define(:token, :user_id, :token_id, :expires_at) do
    include RedactedInspection

    def initialize(**attributes)
      super(**ImmutableValue.copy_attributes(**attributes))
    end

    def inspect
      "#<#{self.class} user_id=#{user_id.inspect} token_id=#{token_id.inspect}>"
    end
  end
end
