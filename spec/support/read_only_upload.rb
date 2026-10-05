# frozen_string_literal: true

require 'stringio'

module SpecSupport
  # A readable stream without size, position, or seek methods.
  class ReadOnlyUpload
    def initialize(bytes)
      @source = StringIO.new(bytes)
    end

    def read(length = nil)
      @source.read(length)
    end
  end
end
