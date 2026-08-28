# frozen_string_literal: true

# Public namespace for Volcano SDK values.
module Volcano
  # Recursively copies JSON-like values into immutable public data.
  module ImmutableValue
    module_function

    def copy(value)
      case value
      when Hash then value.to_h { |key, item| [key.to_s.freeze, copy(item)] }.freeze
      when Array then value.map { |item| copy(item) }.freeze
      else value&.freeze
      end
    end
  end
  private_constant :ImmutableValue

  user_defaults = {
    project_id: nil, email_confirmed: nil, user_metadata: nil,
    app_metadata: nil, avatar_url: nil, status: nil, banned_until: nil,
    last_sign_in_at: nil, created_at: nil, updated_at: nil
  }.freeze

  # Authenticated Volcano user.
  User = Data.define(
    :id, :email, :project_id, :email_confirmed, :user_metadata, :app_metadata,
    :avatar_url, :status, :banned_until, :last_sign_in_at, :created_at, :updated_at
  ) do
    define_method(:initialize) do |id:, email:, **attributes|
      unknown = attributes.keys - user_defaults.keys
      raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?

      values = user_defaults.merge(attributes)
      values[:user_metadata] = ImmutableValue.copy(values[:user_metadata])
      values[:app_metadata] = ImmutableValue.copy(values[:app_metadata])
      super(id:, email:, **values)
    end

    def inspect
      "#<#{self.class} id=#{id.inspect} email=#{email.inspect} status=#{status.inspect}>"
    end
  end

  # Authenticated user session.
  Session = Data.define(:access_token, :refresh_token, :expires_in, :user_id) do
    def initialize(access_token:, refresh_token: nil, expires_in: nil, user_id: nil)
      super
    end

    def inspect
      "#<#{self.class} expires_in=#{expires_in.inspect} user_id=#{user_id.inspect}>"
    end
  end

  # Result of an email-and-password sign-up request.
  SignUpResult = Data.define(
    :confirmation_required, :message, :user, :session
  ) do
    def initialize(confirmation_required:, message:, user: nil, session: nil)
      super
    end
  end

  # Acknowledgement returned by an authentication operation.
  MessageResult = Data.define(:message)

  # Result of an email-change request.
  EmailChangeResult = Data.define(:message, :new_email, :email_change_token) do
    def initialize(message:, new_email:, email_change_token: nil)
      super
    end

    def inspect
      "#<#{self.class} message=#{message.inspect} new_email=#{new_email.inspect}>"
    end
  end

  # Authorization URL and caller-owned state for an authentication flow.
  AuthorizationRequest = Data.define(:authorization_url, :state) do
    def inspect
      "#<#{self.class} authorization_url=[REDACTED] state=[REDACTED]>"
    end
  end

  # OAuth provider linked to the current user.
  OAuthProvider = Data.define(:provider, :linked_at, :updated_at) do
    def initialize(provider:, linked_at: nil, updated_at: nil)
      super
    end
  end

  # Acknowledgement for an OAuth provider-token operation.
  OAuthTokenResult = Data.define(:provider, :expires_in, :message) do
    def initialize(provider:, expires_in: nil, message: nil)
      super
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
      super
    end
  end

  # Page of device sessions associated with the current user.
  SessionPage = Data.define(:sessions, :total, :page, :limit, :total_pages) do
    def initialize(sessions: [], total: nil, page: nil, limit: nil, total_pages: nil)
      super(sessions: sessions.dup.freeze, total:, page:, limit:, total_pages:)
    end
  end

  # Lease returned for an acquired distributed lock.
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)
end
