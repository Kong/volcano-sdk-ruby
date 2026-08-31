# frozen_string_literal: true

module Volcano
  Session = Data.define(:access_token, :refresh_token, :user_id)
  SignUpResult = Data.define(:confirmation_required, :message)
  User = Data.define(:id, :email, :status, :email_confirmed, :user_metadata) do
    def initialize(id:, email:, status:, email_confirmed: nil, user_metadata: nil)
      super(
        id: freeze_value(id),
        email: freeze_value(email),
        status: freeze_value(status),
        email_confirmed: email_confirmed,
        user_metadata: freeze_value(user_metadata)
      )
    end

    private

    def freeze_value(value)
      case value
      when Hash then value.to_h { |key, item| [freeze_value(key), freeze_value(item)] }.freeze
      when Array then value.map { |item| freeze_value(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)
end
