# frozen_string_literal: true

module Volcano
  # In-memory credentials with an optional, unverified local user snapshot.
  Session = Data.define(:access_token, :refresh_token, :user_id, :user) do
    def initialize(access_token:, refresh_token:, user_id:, user: nil)
      super(access_token:, refresh_token:, user_id:, user: immutable_user(user))
    end

    private

    def immutable_user(value)
      case value
      when Hash then value.to_h { |key, item| [immutable_user(key), immutable_user(item)] }.freeze
      when Array then value.map { |item| immutable_user(item) }.freeze
      when String, Time then value.dup.freeze
      else value
      end
    end
  end
end
