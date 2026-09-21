# frozen_string_literal: true

module Volcano
  AUTH_SESSION_ATTRIBUTES = %i[
    id user_id provider expires_at is_active is_current user_agent ip_address last_ip_address
    last_activity_at session_started_at created_at updated_at
  ].freeze
  private_constant :AUTH_SESSION_ATTRIBUTES

  AuthSession = Data.define(*AUTH_SESSION_ATTRIBUTES) do
    def initialize(**attributes)
      unknown = attributes.keys - AUTH_SESSION_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = AUTH_SESSION_ATTRIBUTES.first(6) - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = AUTH_SESSION_ATTRIBUTES.to_h do |name|
        [name, freeze_session_value(attributes[name])]
      end
      super(**values)
    end

    private

    def freeze_session_value(value)
      value.frozen? ? value : value.dup.freeze
    end
  end

  SessionPage = Data.define(:sessions, :total, :page, :limit, :total_pages) do
    def initialize(sessions:, total:, page:, limit:, total_pages:)
      super(sessions: sessions.to_a.dup.freeze, total: total, page: page, limit: limit,
            total_pages: total_pages)
    end
  end
  LinkedOAuthProvider = Data.define(:provider, :linked_at, :updated_at) do
    def initialize(provider:, linked_at:, updated_at:)
      super(
        provider: immutable_value(provider),
        linked_at: immutable_value(linked_at),
        updated_at: immutable_value(updated_at)
      )
    end

    private

    def immutable_value(value)
      value.frozen? ? value : value.dup.freeze
    end
  end
  OAuthProviderTokenStatus = Data.define(:message, :provider, :expires_in) do
    def initialize(message:, provider:, expires_in:)
      values = [message, provider]
      valid = values.all? { |value| value.is_a?(String) && !value.strip.empty? }
      raise TypeError, 'Expected complete OAuth provider token status' unless valid && expires_in.is_a?(Integer)

      super(message: message.dup.freeze, provider: provider.dup.freeze, expires_in: expires_in)
    end
  end
  EmailChangeResult = Data.define(:message, :new_email)
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token) do
    def initialize(key:, token:, expires_at:, fencing_token:)
      super(
        key: key.dup.freeze,
        token: token.dup.freeze,
        expires_at: expires_at&.dup&.freeze,
        fencing_token: fencing_token
      )
    end
  end
  LockState = Data.define(:held, :expires_at, :fencing_token) do
    def initialize(held:, expires_at:, fencing_token:)
      immutable_expiry = expires_at&.then { |value| value.frozen? ? value : value.dup.freeze }
      super(held: held, expires_at: immutable_expiry, fencing_token: fencing_token)
    end
  end
end
