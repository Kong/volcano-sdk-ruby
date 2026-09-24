# frozen_string_literal: true

require 'json'
require 'time'

module Volcano
  SESSION_USER_CODER = JSON::Coder.new(freeze: true, allow_duplicate_key: false) do |value|
    value.instance_of?(Time) ? Time.at(Rational(value)).utc.iso8601(9) : value
  end
  private_constant :SESSION_USER_CODER

  # Local credentials; refresh credentials and user identity may be unknown.
  Session = Data.define(:access_token, :refresh_token, :user_id, :user)

  # Reopens the generated record for checked initialization.
  class Session
    def initialize(access_token:, refresh_token: nil, user_id: nil, user: nil)
      user = immutable_user(user)
      super
    end

    private

    def immutable_user(value)
      return if value.nil?

      snapshot = SESSION_USER_CODER.load(SESSION_USER_CODER.dump(value))
      raise TypeError, 'Session user snapshot must be a Hash' unless snapshot.is_a?(Hash)

      snapshot
    rescue JSON::GeneratorError, JSON::NestingError
      raise TypeError, 'Session user snapshot must contain JSON values or timestamps', cause: nil
    end
  end
end
