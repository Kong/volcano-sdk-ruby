# frozen_string_literal: true

require_relative 'immutable_value'

module Volcano
  # Verified email identity owned by the current user.
  AuthIdentity = Data.define(:id, :email, :email_verified, :is_primary, :created_at) do
    def initialize(id:, email:, email_verified:, is_primary:, created_at:)
      super(**ImmutableValue.copy_attributes(id:, email:, email_verified:, is_primary:, created_at:))
    end
  end

  # Sign-in method owned by the current user.
  AuthMethod = Data.define(
    :id, :type, :identity_id, :email, :is_primary, :created_at, :updated_at,
    :provider, :last_used_at
  ) do
    def initialize(
      id:, type:, identity_id:, email:, is_primary:, created_at:, updated_at:,
      provider: nil, last_used_at: nil
    )
      super(
        **ImmutableValue.copy_attributes(
          id:, type:, identity_id:, email:, is_primary:, created_at:, updated_at:,
          provider:, last_used_at:
        )
      )
    end
  end
end
