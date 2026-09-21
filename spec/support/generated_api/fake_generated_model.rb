# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeGeneratedModel
      def initialize(value)
        @value = value
      end

      def to_hash
        @value
      end
    end
  end
end
