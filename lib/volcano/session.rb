# frozen_string_literal: true

require 'json'
require 'time'

module Volcano
  SESSION_USER_CODER = JSON::Coder.new(freeze: true, allow_duplicate_key: false) do |value|
    value.instance_of?(Time) ? Time.at(value.to_r).utc.iso8601(9) : value
  end
  private_constant :SESSION_USER_CODER

  # In-memory credentials with an optional, unverified local user snapshot.
  Session = Data.define(:access_token, :refresh_token, :user_id, :user) do
    def initialize(access_token:, refresh_token:, user_id:, user: nil)
      super(access_token:, refresh_token:, user_id:, user: immutable_user(user))
    end

    private

    def immutable_user(value)
      SESSION_USER_CODER.load(SESSION_USER_CODER.dump(value))
    rescue JSON::GeneratorError, JSON::NestingError
      raise TypeError, 'Session user snapshot must contain JSON values or timestamps', cause: nil
    end
  end
end
