# frozen_string_literal: true

module SpecSupport
  # Coordinates reads around the rejected-refresh credential removal boundary.
  class RefreshRejectionSignals
    attr_reader :started, :release_read, :cleared, :finish_clear, :results

    def initialize
      @started = Queue.new
      @release_read = Queue.new
      @cleared = Queue.new
      @finish_clear = Queue.new
      @results = Queue.new
    end
  end
end
