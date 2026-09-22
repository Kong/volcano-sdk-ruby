# frozen_string_literal: true

module SpecSupport
  # A readable download without seek, binary-mode, or tempfile lifecycle methods.
  class ReadOnlyDownload
    def initialize(content)
      @content = content
    end

    def read = @content
  end
end
