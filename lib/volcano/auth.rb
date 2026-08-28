# frozen_string_literal: true

require 'openssl'
require 'securerandom'
require 'time'
require 'uri'

require_relative 'auth_mapping'
require_relative 'auth_invocation'
require_relative 'auth_lifecycle'
require_relative 'auth_account'
require_relative 'auth_oauth'

module Volcano
  # Authenticates users and updates client-owned auth state.
  class Auth
    include AuthMapping
    include AuthInvocation
    include AuthLifecycle
    include AuthAccount
    include AuthOAuth

    def initialize(client, transport)
      @client = client
      @transport = transport
    end
  end
end
