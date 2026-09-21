# frozen_string_literal: true

require_relative 'facade/fake_user_transport'
require_relative 'facade/fake_password_recovery_transport'
require_relative 'facade/fake_email_confirmation_transport'
require_relative 'facade/fake_call_log'
require_relative 'facade/fake_email_change_transport'
require_relative 'facade/fake_session_transport'
require_relative 'facade/fake_o_auth_transport'
require_relative 'facade/fake_anonymous_transport'
require_relative 'facade/fake_database_transport'
require_relative 'facade/fake_storage_transport'
require_relative 'facade/fake_upload_session_transport'
require_relative 'facade/fake_lock_transport'

module SpecSupport
  module Facade
    FakeEmailChangeTransport.include(FakeOAuthTransport)

    class FakeContractTransport
      include FakeDatabaseTransport
      include FakeLockTransport
      include FakeStorageTransport
      include FakeUploadSessionTransport

      include FakeCallLog
      include FakeEmailChangeTransport
      include FakeAnonymousTransport
      include FakeEmailConfirmationTransport
      include FakePasswordRecoveryTransport
      include FakeUserTransport

      attr_reader :calls
      attr_accessor :access_token, :logout_response, :on_logout, :on_refresh, :on_signin, :range_download_status,
                    :refresh_response, :signup_response, :on_signup

      def initialize
        @access_token = 'access-token'
        @range_download_status = 206
        @signup_response = Volcano::Transport::Response.new(
          status: 201,
          body: {
            'confirmation_required' => true,
            'message' => 'Check your email to confirm your account'
          },
          headers: {},
          data: nil
        )
        initialize_auth_responses
        @user_response = Volcano::Transport::Response.new(
          status: 200,
          body: {
            'user' => {
              'id' => 'user-123',
              'email' => 'user@example.com',
              'status' => 'active',
              'email_confirmed' => true,
              'user_metadata' => { 'display_name' => 'Ada', 'roles' => ['admin'] }
            }
          },
          headers: {},
          data: nil
        )
        @update_user_response = @user_response
        @refresh_response = Volcano::Transport::Response.new(
          status: 200,
          body: {
            'access_token' => 'access-2',
            'refresh_token' => 'refresh-2',
            'user' => { 'id' => 'user-123' }
          },
          headers: {},
          data: nil
        )
        @logout_response = Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
        @calls = []
      end

      def auth_logout(**arguments)
        @calls << [:auth_logout, arguments]
        @logout_response.tap { @on_logout&.call }
      end

      def auth_refresh(**arguments)
        @calls << [:auth_refresh, arguments]
        @on_refresh&.call
        @refresh_response
      end

      def auth_signin(**arguments)
        @calls << [:auth_signin, arguments]
        @on_signin&.call
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'access_token' => access_token,
            'refresh_token' => 'refresh-token',
            'user' => { 'id' => 'user-123' }
          },
          headers: {},
          data: nil
        )
      end

      def auth_signup(**arguments)
        @calls << [:auth_signup, arguments]
        @on_signup&.call
        @signup_response
      end
    end
  end
end
