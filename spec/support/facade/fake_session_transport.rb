# frozen_string_literal: true

module SpecSupport
  module Facade
    module FakeSessionTransport
      attr_accessor :delete_session_response, :list_sessions_response, :on_delete_other_sessions,
                    :on_delete_session, :on_list_sessions

      def auth_get_my_sessions(**arguments)
        @calls << [:auth_get_my_sessions, arguments]
        @on_list_sessions&.call
        @list_sessions_response || Volcano::Transport::Response.new(
          status: 200,
          body: {
            'sessions' => [
              {
                'id' => '00000000-0000-4000-8000-000000000099',
                'user_id' => '00000000-0000-4000-8000-000000000010',
                'provider' => 'email',
                'user_agent' => 'Volcano Test',
                'ip_address' => '192.0.2.10',
                'last_ip_address' => '192.0.2.11',
                'expires_at' => Time.iso8601('2026-09-02T12:00:00Z'),
                'last_activity_at' => Time.iso8601('2026-09-01T12:00:00Z'),
                'session_started_at' => Time.iso8601('2026-08-31T12:00:00Z'),
                'is_active' => true,
                'is_current' => true,
                'created_at' => Time.iso8601('2026-08-31T12:00:00Z'),
                'updated_at' => Time.iso8601('2026-09-01T12:00:00Z')
              }
            ],
            'total' => 21,
            'page' => 2,
            'limit' => 10,
            'total_pages' => 3
          },
          headers: {},
          data: nil
        )
      end

      def auth_delete_all_my_sessions(**arguments)
        @calls << [:auth_delete_all_my_sessions, arguments]
        @on_delete_other_sessions&.call
        Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
      end

      def auth_delete_my_session(**arguments)
        @calls << [:auth_delete_my_session, arguments]
        @on_delete_session&.call
        @delete_session_response || Volcano::Transport::Response.new(status: 204, body: nil, headers: {}, data: nil)
      end
    end

    FakeEmailChangeTransport.include(FakeSessionTransport)
  end
end
