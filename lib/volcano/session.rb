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
      when String, Time then plain_leaf(value).freeze
      when Integer, Float, TrueClass, FalseClass, NilClass then value
      else raise TypeError, 'Session user snapshot must contain JSON values or timestamps'
      end
    end

    def plain_leaf(value)
      value.is_a?(String) ? String.new(value) : Time.at(value)
    end
  end
end
