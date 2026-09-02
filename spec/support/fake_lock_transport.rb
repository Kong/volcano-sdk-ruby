# frozen_string_literal: true

module SpecSupport
  # Configurable lock transport for renewal lifecycle tests.
  class FakeLockTransport
    attr_accessor :acquire_expires_at, :renew_handler
    attr_reader :calls

    def initialize
      @calls = []
      @acquire_expires_at = Time.now.utc + 30
      @renew_handler = nil
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
      response(204, nil)
    end

    def response(status, body)
      Volcano::Transport::Response.new(status: status, body: body, headers: {}, data: nil)
    end
  end
end
