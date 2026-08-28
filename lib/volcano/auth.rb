# frozen_string_literal: true

require 'openssl'
require 'monitor'
require 'securerandom'
require 'time'
require 'uri'

require_relative 'auth_mapping'
require_relative 'auth_signup_mapping'
require_relative 'auth_invocation'
require_relative 'auth_lifecycle'
require_relative 'auth_account'
require_relative 'auth_oauth'
require_relative 'auth_sessions'

module Volcano
  # Authenticates users and updates client-owned auth state.
  class Auth
    include AuthMapping
    include AuthSignupMapping
    include AuthInvocation
    include AuthLifecycle
    include AuthAccount
    include AuthOAuth
    include AuthSessions

    def initialize(client, transport)
      @client = client
      @transport = transport
      @refresh_mutex = Mutex.new
      @operation_monitor = Monitor.new
      @current_device_session_ids = [].freeze
    end

    def store_session(session)
      synchronize_auth_operation { @client.commit_auth(session, nil) }
    end

    private

    def synchronize_auth_operation(&)
      @operation_monitor.synchronize(&)
    end
  end
end
