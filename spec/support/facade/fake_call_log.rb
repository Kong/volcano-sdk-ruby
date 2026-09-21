# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeCallLog
      def calls_for(name)
        calls.select { |call| call.first == name }
      end
    end
  end
end
