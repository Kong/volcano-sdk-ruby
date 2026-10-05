# frozen_string_literal: true

require 'stringio'

module SpecSupport
  module Facade
    CallbackAbort = Exception

    class BoundedReadIO < StringIO
      attr_reader :read_lengths

      def initialize(value)
        super
        @read_lengths = []
      end

      def read(length = nil, output = nil)
        raise 'unbounded read' if length.nil?

        @read_lengths << length
        super
      end
    end

    class BoundedNonSeekableIO
      attr_reader :read_lengths

      def initialize(value)
        @value = value.b
        @offset = 0
        @read_lengths = []
      end

      def read(length = nil)
        raise 'unbounded read' if length.nil?

        @read_lengths << length
        return if @offset >= @value.bytesize

        chunk = @value.byteslice(@offset, length)
        @offset += chunk.bytesize
        chunk
      end
    end
  end
end
