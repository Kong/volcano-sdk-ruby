# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeEmailConfirmationTransport
      attr_accessor :confirm_email_response, :resend_confirmation_response

      def initialize_email_confirmation_response
        @confirm_email_response = Volcano::Transport::Response.new(
          status: 200, body: { 'message' => 'Email confirmed successfully' }, headers: {}, data: nil
        )
        @resend_confirmation_response = Volcano::Transport::Response.new(
          status: 200, body: { 'message' => 'If eligible, a confirmation email has been sent.' },
          headers: {}, data: nil
        )
      end

      def auth_confirm_email(**arguments)
        @calls << [:auth_confirm_email, arguments]
        @confirm_email_response
      end

      def auth_resend_confirmation(**arguments)
        @calls << [:auth_resend_confirmation, arguments]
        @resend_confirmation_response
      end
    end
  end
end
