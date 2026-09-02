# frozen_string_literal: true

module SpecSupport
  # Controllable paired clock for lease lifecycle tests.
  class FakeLeaseClock
    attr_reader :monotonic, :wall

    def initialize
      @monotonic = 0.0
      @wall = Time.now
    end

    def advance(seconds)
      @monotonic += seconds
      @wall += seconds
    end
  end

  # Configurable lock transport for renewal lifecycle tests.
  class FakeLockTransport
    attr_accessor :acquire_expires_at, :release_handler, :renew_handler
    attr_reader :calls

    def initialize
      @calls = []
      @acquire_expires_at = Time.now.utc + 30
      @renew_handler = nil
      @release_handler = nil
    end

    def acquire_project_lock(**arguments)
      @calls << [:acquire_project_lock, arguments]
      response(201, 'expires_at' => acquire_expires_at.iso8601(6), 'fencing_token' => 7)
    end

    def renew_project_lock(**arguments)
      @calls << [:renew_project_lock, arguments]
      return renew_handler.call(arguments) if renew_handler

      response(200, 'expires_at' => (Time.now.utc + 30).iso8601(6), 'fencing_token' => 8)
    end

    def release_project_lock(**arguments)
      @calls << [:release_project_lock, arguments]
      return release_handler.call(arguments) if release_handler

      response(204, nil)
    end

    def response(status, body)
      Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
    end
  end
end
