# frozen_string_literal: true

require 'base64'
require 'json'
require_relative 'session'

module Volcano
  # Owns credential snapshots and preserves validated identity during refresh.
  module SessionCredentials
    def self.build(access_token, refresh_token)
      raise ArgumentError, 'refresh_token requires access_token' if access_token.nil? && !refresh_token.nil?
      return if access_token.nil?

      Session.new(access_token: credential(access_token, :access_token),
                  refresh_token: refresh_token.nil? ? nil : credential(refresh_token, :refresh_token))
    end

    def self.credential(value, name)
      raise ArgumentError, "#{name} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

      value.dup.freeze
    end
    private_class_method :credential

    def self.validate_refresh_source(current, verified: false)
      return if verified || session_id(current.access_token)

      raise Error::AuthenticationError, 'Cannot refresh supplied credentials without a session identifier'
    end

    def self.validate_refresh(current, refreshed)
      return unless current

      validate_refresh_session_id(current, refreshed)
      return unless current.user_id && current.user_id != refreshed&.user_id

      raise Error::AuthenticationError, 'Refreshed session belongs to a different user'
    end

    def self.validate_refresh_session_id(current, refreshed)
      expected = session_id(current.access_token)
      return unless expected && expected != session_id(refreshed&.access_token)

      raise Error::AuthenticationError, 'Refreshed credentials belong to a different server session'
    end
    private_class_method :validate_refresh_session_id

    # Untrusted continuity constraint, never authenticated user identity.
    def self.session_id(access_token)
      payload = token_payload(access_token)
      return unless payload.is_a?(Hash)

      value = payload['session_id']
      value.downcase if value.is_a?(String) && value.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    end

    def self.token_payload(access_token)
      return unless access_token.is_a?(String)

      parts = access_token.split('.')
      return unless parts.length == 3

      encoded = parts.fetch(1).tr('-_', '+/')
      JSON.parse(Base64.strict_decode64(encoded + ('=' * (-encoded.length % 4))))
    rescue ArgumentError, JSON::ParserError
      nil
    end
    private_class_method :token_payload

    def self.with_user(session, user)
      user_id = session.user_id || user.fetch('id')
      raise Error::AuthenticationError, 'Profile has no valid user identifier' unless user_id.is_a?(String)

      user_id = user_id.dup.freeze
      raise Error::AuthenticationError, 'Profile belongs to a different user' unless user['id'] == user_id

      Session.new(access_token: session.access_token, refresh_token: session.refresh_token,
                  user_id: user_id, user: user)
    end
  end
  private_constant :SessionCredentials
end
