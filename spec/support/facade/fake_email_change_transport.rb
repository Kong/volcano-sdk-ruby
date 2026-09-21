# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeEmailChangeTransport
      attr_accessor :cancel_email_change_response, :email_change_response,
                    :confirm_email_change_response, :on_cancel_email_change,
                    :on_confirm_email_change, :on_email_change

      def initialize_email_change_response
        @email_change_response = Volcano::Transport::Response.new(
          status: 200,
          body: { 'message' => 'Confirmation email sent', 'new_email' => 'new@example.com' },
          headers: {}, data: nil
        )
        @cancel_email_change_response = Volcano::Transport::Response.new(status: 200, body: {}, headers: {}, data: nil)
        @confirm_email_change_response = Volcano::Transport::Response.new(
          status: 200,
          body: {
            'user' => { 'id' => 'user-123', 'email' => 'new@example.com', 'status' => 'active' }
          },
          headers: {}, data: nil
        )
      end

      def auth_request_email_change(**arguments)
        @calls << [:auth_request_email_change, arguments]
        @on_email_change&.call
        @email_change_response
      end

      def auth_cancel_email_change(**arguments)
        @calls << [:auth_cancel_email_change, arguments]
        @on_cancel_email_change&.call
        @cancel_email_change_response
      end

      def auth_confirm_email_change(**arguments)
        @calls << [:auth_confirm_email_change, arguments]
        @on_confirm_email_change&.call
        @confirm_email_change_response
      end
    end
  end
end
