# frozen_string_literal: true

module Volcano
  Session = Data.define(:access_token, :refresh_token, :user_id)
  SignUpResult = Data.define(:confirmation_required, :message)
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)
end
