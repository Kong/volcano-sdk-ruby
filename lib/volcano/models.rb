# frozen_string_literal: true

module Volcano
  Session = Data.define(:access_token, :refresh_token, :user_id)
  LockLease = Data.define(:key, :token, :expires_at, :fencing_token)
end
