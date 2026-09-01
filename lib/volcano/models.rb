# frozen_string_literal: true

module Volcano
  Session = Data.define(:access_token, :refresh_token, :user_id)
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
      super(sessions: sessions.to_a.freeze, total: total, page: page, limit: limit,
            total_pages: total_pages)
    end
  end
  SignUpResult = Data.define(:confirmation_required, :message)
  EmailChangeResult = Data.define(:message, :new_email)
  USER_OPTIONAL_ATTRIBUTES = %i[
    project_id email_confirmed user_metadata app_metadata avatar_url banned_until
    last_sign_in_at created_at updated_at
  ].freeze
  private_constant :USER_OPTIONAL_ATTRIBUTES

  User = Data.define(
    :id, :project_id, :email, :email_confirmed, :user_metadata, :app_metadata,
    :avatar_url, :status, :banned_until, :last_sign_in_at, :created_at, :updated_at
  ) do
    def initialize(id:, email:, status:, **attributes)
      validate_optional_attributes(attributes)
      super(
        id: freeze_value(id),
        email: freeze_value(email),
        status: freeze_value(status),
        **USER_OPTIONAL_ATTRIBUTES.to_h { |name| [name, freeze_value(attributes[name])] }
      )
    end

    private

    def validate_optional_attributes(attributes)
      unknown = attributes.keys - USER_OPTIONAL_ATTRIBUTES
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?
    end

    def freeze_value(value)
      case value
      when Hash then value.to_h { |key, item| [freeze_value(key), freeze_value(item)] }.freeze
      when Array then value.map { |item| freeze_value(item) }.freeze
      when String then value.dup.freeze
      else value.frozen? ? value : value.dup.freeze
      end
    end
  end
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)
end
