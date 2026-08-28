# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  # Implements current-user device-session operations.
  module AuthSessions
    def get_sessions(page: 1, limit: 20)
      payload = mapping(authenticated_body(:auth_get_my_sessions, 200, page:, limit:))
      SessionPage.new(**session_page_attributes(payload))
    end

    def delete_session(session_id:)
      authenticated_body(:auth_delete_my_session, 204, session_id:)
      nil
    end

    def delete_all_other_sessions
      authenticated_body(:auth_delete_all_my_sessions, 204)
      nil
    end

    private

    def session_page_attributes(payload)
      {
        sessions: auth_sessions(payload), total: payload['total'], page: payload['page'],
        limit: payload['limit'], total_pages: payload['total_pages']
      }
    end

    def auth_sessions(payload)
      array(payload['sessions'] || payload['data']).map do |session|
        build_auth_session(mapping(session))
      end
    end
  end
  private_constant :AuthSessions
end
