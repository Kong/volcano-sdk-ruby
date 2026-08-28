# frozen_string_literal: true

require_relative 'immutable_value'

# Public namespace for Volcano SDK values.
module Volcano
  # Uses a class's redacted inspection for pretty-printer output.
  module RedactedInspection
    def pretty_print(printer)
      printer.text(inspect)
    end
  end
  private_constant :RedactedInspection

  # Authenticated Volcano user.
  User = Data.define(
    :id, :email, :project_id, :email_confirmed, :user_metadata, :app_metadata,
    :avatar_url, :status, :banned_until, :last_sign_in_at, :created_at, :updated_at
  ) do
    def initialize(id:, email:, **attributes)
      super(
        id: ImmutableValue.copy(id), email: ImmutableValue.copy(email),
        **ImmutableValue.user_attributes(attributes)
      )
    end

    def inspect
      "#<#{self.class} id=#{id.inspect} email=#{email.inspect} status=#{status.inspect}>"
    end
  end

  # Authenticated user session.
  Session = Data.define(:access_token, :refresh_token, :user_id, :expires_in) do
    include RedactedInspection

    def initialize(access_token:, refresh_token: nil, expires_in: nil, user_id: nil)
      super(
        access_token: ImmutableValue.copy(access_token),
        refresh_token: ImmutableValue.copy(refresh_token),
        expires_in:, user_id: ImmutableValue.copy(user_id)
      )
    end

    def inspect
      "#<#{self.class} expires_in=#{expires_in.inspect} user_id=#{user_id.inspect}>"
    end
    alias_method :to_s, :inspect
  end

  # Result of an email-and-password sign-up request.
  SignUpResult = Data.define(
    :confirmation_required, :message, :user, :session
  ) do
    def initialize(confirmation_required:, message:, user: nil, session: nil)
      super(
        **ImmutableValue.copy_attributes(confirmation_required:, message:, user:, session:)
      )
    end
  end

  # Acknowledgement returned by an authentication operation.
  MessageResult = Data.define(:message) do
    def initialize(message:)
      super(message: ImmutableValue.copy(message))
    end
  end

  # Result of an email-change request.
  EmailChangeResult = Data.define(:message, :new_email, :email_change_token) do
    include RedactedInspection

    def initialize(message:, new_email:, email_change_token: nil)
      super(
        message: ImmutableValue.copy(message), new_email: ImmutableValue.copy(new_email),
        email_change_token: ImmutableValue.copy(email_change_token)
      )
    end

    def inspect
      "#<#{self.class} message=#{message.inspect} new_email=#{new_email.inspect}>"
    end
    alias_method :to_s, :inspect
  end

  # Authorization URL and caller-owned state for an authentication flow.
  AuthorizationRequest = Data.define(:authorization_url, :state) do
    include RedactedInspection

    def initialize(authorization_url:, state:)
      super(
        authorization_url: ImmutableValue.copy(authorization_url),
        state: ImmutableValue.copy(state)
      )
    end

    def inspect
      "#<#{self.class} authorization_url=[REDACTED] state=[REDACTED]>"
    end
    alias_method :to_s, :inspect
  end

  # OAuth provider linked to the current user.
  OAuthProvider = Data.define(:provider, :linked_at, :updated_at) do
    def initialize(provider:, linked_at: nil, updated_at: nil)
      super(**ImmutableValue.copy_attributes(provider:, linked_at:, updated_at:))
    end
  end

  # Acknowledgement for an OAuth provider-token operation.
  OAuthTokenResult = Data.define(:provider, :expires_in, :message) do
    def initialize(provider:, expires_in: nil, message: nil)
      super(**ImmutableValue.copy_attributes(provider:, expires_in:, message:))
    end
  end

  # Device session associated with the current user.
  AuthSession = Data.define(
    :id, :user_id, :provider, :expires_at, :is_active, :is_current,
    :user_agent, :ip_address, :last_ip_address, :last_activity_at,
    :session_started_at, :created_at, :updated_at
  ) do
    def initialize(
      id:, user_id:, provider:, expires_at:, is_active:, is_current:,
      user_agent: nil, ip_address: nil, last_ip_address: nil,
      last_activity_at: nil, session_started_at: nil, created_at: nil,
      updated_at: nil
    )
      super(
        **ImmutableValue.copy_attributes(
          id:, user_id:, provider:, expires_at:, is_active:, is_current:,
          user_agent:, ip_address:, last_ip_address:, last_activity_at:,
          session_started_at:, created_at:, updated_at:
        )
      )
    end
  end
end
