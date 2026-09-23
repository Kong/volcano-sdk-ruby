# frozen_string_literal: true

module Volcano
  AUTH_SESSION_ATTRIBUTES = %i[
    id user_id provider expires_at is_active is_current user_agent ip_address last_ip_address
    last_activity_at session_started_at created_at updated_at
  ].freeze
  private_constant :AUTH_SESSION_ATTRIBUTES

  AuthSession = Data.define(*AUTH_SESSION_ATTRIBUTES)

  # Reopens the generated record for checked initialization.
  class AuthSession
    # @dynamic id, user_id, provider, expires_at, is_active, is_current, user_agent
    # @dynamic ip_address, last_ip_address, last_activity_at, session_started_at
    # @dynamic created_at, updated_at, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(**attributes)
      unknown = attributes.keys - AUTH_SESSION_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      missing = AUTH_SESSION_ATTRIBUTES.first(6) - attributes.keys
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?

      values = AUTH_SESSION_ATTRIBUTES.to_h do |name|
        [name, freeze_session_value(attributes[name])]
      end
      attributes = values
      super
    end

    private

    def freeze_session_value(value)
      value.frozen? ? value : value.dup.freeze
    end
  end

  SessionPage = Data.define(:sessions, :total, :page, :limit, :total_pages)

  # Reopens the generated record for checked initialization.
  class SessionPage
    # @dynamic sessions, total, page, limit, total_pages, members, with, to_h
    # @dynamic deconstruct, deconstruct_keys, self.[], self.members
    def initialize(sessions:, total:, page:, limit:, total_pages:)
      sessions = sessions.to_a.dup.freeze
      super
    end
  end
  LinkedOAuthProvider = Data.define(:provider, :linked_at, :updated_at)

  # Reopens the generated record for checked initialization.
  class LinkedOAuthProvider
    # @dynamic provider, linked_at, updated_at, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(provider:, linked_at:, updated_at:)
      provider = immutable_value(provider)
      linked_at = immutable_value(linked_at)
      updated_at = immutable_value(updated_at)
      super
    end

    private

    def immutable_value(value)
      value.frozen? ? value : value.dup.freeze
    end
  end
  OAuthProviderTokenStatus = Data.define(:message, :provider, :expires_in)

  # Reopens the generated record for checked initialization.
  class OAuthProviderTokenStatus
    # @dynamic message, provider, expires_in, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(message:, provider:, expires_in:)
      values = [message, provider]
      valid = values.all? { |value| value.is_a?(String) && !value.strip.empty? }
      raise TypeError, 'Expected complete OAuth provider token status' unless valid && expires_in.is_a?(Integer)

      message = message.dup.freeze
      provider = provider.dup.freeze
      super
    end
  end
  EmailChangeResult = Data.define(:message, :new_email)
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)

  # Reopens the generated record for checked initialization.
  class LockLease
    # @dynamic key, token, expires_at, fencing_token, members, with, to_h
    # @dynamic deconstruct, deconstruct_keys, self.[], self.members
    def initialize(key:, token:, expires_at:, fencing_token:)
      key = key.dup.freeze
      token = token.dup.freeze
      expires_at = expires_at&.dup&.freeze
      super
    end
  end
  LockState = Data.define(:held, :expires_at, :fencing_token)

  # Reopens the generated record for checked initialization.
  class LockState
    # @dynamic held, expires_at, fencing_token, members, with, to_h, deconstruct
    # @dynamic deconstruct_keys, self.[], self.members
    def initialize(held:, expires_at:, fencing_token:)
      immutable_expiry = expires_at&.then { |value| value.frozen? ? value : value.dup.freeze }
      expires_at = immutable_expiry
      super
    end
  end
end
