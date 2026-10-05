# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeAnonymousTransport
      attr_accessor :anonymous_conversion_response, :anonymous_signin_response,
                    :on_anonymous_conversion, :on_anonymous_signin

      def initialize_anonymous_signin_response
        @anonymous_signin_response = Volcano::Transport::Response.new(
          status: 201,
          body: {
            'access_token' => 'anonymous-access',
            'refresh_token' => 'anonymous-refresh',
            'user' => { 'id' => 'anonymous-user' }
          },
          headers: {},
          data: nil
        )
      end

      def initialize_auth_responses
        initialize_password_recovery_response
        initialize_email_confirmation_response
        initialize_anonymous_signin_response
        initialize_email_change_response
        @anonymous_conversion_response = Volcano::Transport::Response.new(
          status: 200,
          body: {
            'user' => {
              'id' => 'anonymous-user', 'email' => 'converted@example.com',
              'status' => 'active', 'email_confirmed' => false
            }
          },
          headers: {}, data: nil
        )
      end

      def auth_signup_anonymous(**arguments)
        @calls << [:auth_signup_anonymous, arguments]
        @on_anonymous_signin&.call
        @anonymous_signin_response
      end

      def auth_convert_anonymous(**arguments)
        @calls << [:auth_convert_anonymous, arguments]
        @on_anonymous_conversion&.call
        @anonymous_conversion_response
      end
    end

    # Implements the database operations used by the facade test transport.
  end
end
