# frozen_string_literal: true

require 'json'
require 'time'

module Volcano
  SESSION_USER_CODER = JSON::Coder.new(freeze: true, allow_duplicate_key: false) do |value|
    value.instance_of?(Time) ? Time.at(value.to_r).utc.iso8601(9) : value
  end
  private_constant :SESSION_USER_CODER

  # Copies caller-owned credentials without inventing a validated identity.
  module SessionBootstrap
    def self.build(access_token, refresh_token)
      raise ArgumentError, 'refresh_token requires access_token' if access_token.nil? && !refresh_token.nil?
      return if access_token.nil?

      Session.new(access_token: credential(access_token, :access_token),
                  refresh_token: credential(refresh_token, :refresh_token))
    end

    def self.credential(value, name)
      return if value.nil?

      raise ArgumentError, "#{name} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

      value.dup.freeze
    end
    private_class_method :credential
  end
  private_constant :SessionBootstrap

  # Local credentials; refresh credentials and user identity may be unknown.
  Session = Data.define(:access_token, :refresh_token, :user_id, :user) do
    def initialize(access_token:, refresh_token: nil, user_id: nil, user: nil)
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
