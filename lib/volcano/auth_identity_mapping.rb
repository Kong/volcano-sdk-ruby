# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Validates and maps user identities and their token sessions.
  module AuthIdentityMapping
    USER_FIELDS = %w[
      project_id email_confirmed user_metadata app_metadata avatar_url
      banned_until last_sign_in_at created_at updated_at
    ].freeze
    USER_STATUSES = %w[active banned deleted].freeze
    USER_TIME_FIELDS = %i[banned_until last_sign_in_at created_at updated_at].freeze

    private

    def build_user(payload)
      User.new(
        id: required_identity_field(payload, 'id'),
        email: required_identity_field(payload, 'email'),
        **user_attributes(payload)
      )
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def required_identity_field(payload, field)
      value = payload.fetch(field)
      return value if value.is_a?(String) && !value.empty?

      raise auth_response_error
    end

    def user_attributes(payload)
      attributes = USER_FIELDS.to_h do |field|
        key = field.to_sym
        value = payload[field]
        [key, USER_TIME_FIELDS.include?(key) ? optional_time(value) : value]
      end
      attributes.merge(status: user_status(payload))
    end

    def user_status(payload)
      status = payload.fetch('status')
      return status if USER_STATUSES.include?(status)

      raise auth_response_error
    end

    def build_session(payload)
      user = build_user(mapping(payload.fetch('user')))
      session = Session.new(
        access_token: required_access_token(payload),
        refresh_token: payload['refresh_token'],
        expires_in: required_expires_in(payload),
        user_id: user.id
      )
      [session, user]
    rescue KeyError, TypeError
      raise auth_response_error
    end

    def required_access_token(payload)
      access_token = payload.fetch('access_token')
      return access_token if access_token.is_a?(String) && !access_token.empty?

      raise auth_response_error
    end

    def required_expires_in(payload)
      expires_in = payload.fetch('expires_in')
      return expires_in if expires_in.is_a?(Integer)

      raise auth_response_error
    end
  end
  private_constant :AuthIdentityMapping
end
