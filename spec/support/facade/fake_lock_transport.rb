# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeLockTransport
      def acquire_project_lock(**arguments)
        @calls << [:acquire_project_lock, arguments]
        Volcano::Transport::Response.new(
          status: 201,
          body: { 'expires_at' => Time.iso8601('2026-08-26T12:00:30Z'), 'fencing_token' => 7 },
          headers: {},
          data: nil
        )
      end

      def release_project_lock(**arguments)
        @calls << [:release_project_lock, arguments]
        Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
      end

      def get_project_lock(**arguments)
        @calls << [:get_project_lock, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: {
            'held' => true,
            'expires_at' => '2026-08-26T12:00:30Z',
            'fencing_token' => 7
          },
          headers: {}, data: nil
        )
      end

      def renew_project_lock(**arguments)
        @calls << [:renew_project_lock, arguments]
        Volcano::Transport::Response.new(
          status: 200,
          body: { 'expires_at' => '2026-08-26T12:01:00Z', 'fencing_token' => 7 },
          headers: {}, data: nil
        )
      end

      def force_release_project_lock(**arguments)
        @calls << [:force_release_project_lock, arguments]
        Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
      end
    end
  end
end
