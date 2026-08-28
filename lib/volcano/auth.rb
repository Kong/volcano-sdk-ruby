# frozen_string_literal: true

require 'openssl'
require 'monitor'
require 'securerandom'
require 'time'
require 'uri'

require_relative 'auth_identity_mapping'
require_relative 'auth_mapping'
require_relative 'auth_signup_mapping'
require_relative 'auth_invocation'
require_relative 'auth_lifecycle'
require_relative 'auth_user_state'
require_relative 'auth_account'
require_relative 'auth_provider_errors'
require_relative 'auth_provider_requests'
require_relative 'auth_oauth'
require_relative 'auth_methods'
require_relative 'auth_device'
require_relative 'auth_sessions'

module Volcano
  # Authenticates users and updates client-owned auth state.
  class Auth
    include AuthIdentityMapping
    include AuthMapping
    include AuthSignupMapping
    include AuthInvocation
    include AuthLifecycle
    include AuthUserState
    include AuthAccount
    include AuthProviderRequests
    include AuthOAuth
    include AuthMethods
    include AuthDevice
    include AuthSessions

    def initialize(client, transport)
      @client = client
      @transport = transport
      @refresh_mutex = Mutex.new
      @operation_monitor = Monitor.new
      @current_device_session_ids = [].freeze
    end

    def store_session(session)
      validate_stored_session(session)
      synchronize_auth_operation do
        @current_device_session_ids = [].freeze
        @client.commit_auth(session, nil)
      end
    end

    private

    def validate_stored_session(session)
      raise Error::ValidationError, 'Invalid session' unless valid_stored_session?(session)
    end

    def valid_stored_session?(session)
      return false unless session.is_a?(Session)

      valid_token?(session.access_token) && valid_optional_token?(session.refresh_token)
    end

    def valid_token?(token)
      token.is_a?(String) && !token.empty?
    end

    def valid_optional_token?(token)
      token.nil? || valid_token?(token)
    end

    def synchronize_auth_operation(&)
      @client.defer_auth_notifications(@operation_monitor, &)
    end
  end
end
