# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeUserTransport
      attr_accessor :on_get_user, :on_update_user, :update_user_response, :user_response

      def auth_get_user(**arguments)
        @calls << [:auth_get_user, arguments]
        @user_response.tap { @on_get_user&.call }
      end

      def auth_update_user(**arguments)
        @calls << [:auth_update_user, arguments]
        @update_user_response.tap { @on_update_user&.call }
      end
    end
  end
end
