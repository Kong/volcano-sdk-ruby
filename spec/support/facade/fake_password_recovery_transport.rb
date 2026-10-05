# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakePasswordRecoveryTransport
      attr_accessor :forgot_password_response, :reset_password_response

      def initialize_password_recovery_response
        @forgot_password_response = Volcano::Transport::Response.new(
          status: 200,
          body: { 'message' => 'If the email exists, a password reset link has been sent.' },
          headers: {},
          data: nil
        )
        @reset_password_response = Volcano::Transport::Response.new(
          status: 200,
          body: { 'message' => 'Password reset successful. Please sign in again.' },
          headers: {},
          data: nil
        )
      end

      def auth_forgot_password(**arguments)
        @calls << [:auth_forgot_password, arguments]
        @forgot_password_response
      end

      def auth_reset_password(**arguments)
        @calls << [:auth_reset_password, arguments]
        @reset_password_response
      end
    end
  end
end
