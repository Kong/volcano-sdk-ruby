# frozen_string_literal: true

module Volcano
  Session = Data.define(:access_token, :refresh_token, :user_id)
  SignUpResult = Data.define(:confirmation_required, :message)
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
