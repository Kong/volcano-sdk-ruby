# frozen_string_literal: true

# Public namespace for Volcano SDK authentication.
module Volcano
  SESSION_PAGE_FIELDS = %i[
    total page limit total_pages has_more next_cursor prev_cursor
  ].freeze

  # Page of device sessions associated with the current user.
  SessionPage = Data.define(:sessions, *SESSION_PAGE_FIELDS) do
    def initialize(sessions: [], **attributes)
      unknown = attributes.keys - SESSION_PAGE_FIELDS
      raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?

      values = SESSION_PAGE_FIELDS.to_h { |field| [field, attributes[field]] }
      super(**ImmutableValue.copy_attributes(sessions:, **values))
    end
  end
  private_constant :SESSION_PAGE_FIELDS

  # Implements current-user device-session operations.
  module AuthSessions
    SESSION_OPTIONS = %i[sort status cursor ending_before offset].freeze

    def get_sessions(page: nil, limit: 20, **options)
      synchronize_auth_operation do
        query = session_query(page:, limit:, options:)
        payload = mapping(authenticated_body(:auth_get_my_sessions, 200, **query))
        sessions = auth_sessions(payload)
        record_current_sessions(sessions)
        SessionPage.new(**session_page_attributes(payload, sessions))
      end
    end

    def delete_session(session_id:)
      synchronize_auth_operation do
        deletes_current_session = @current_device_session_ids.include?(session_id)
        authenticated_body(:auth_delete_my_session, 204, session_id:)
        if deletes_current_session
          @current_device_session_ids = [].freeze
          @client.clear_auth
        end
      end
      nil
    end

    def delete_all_other_sessions
      authenticated_body(:auth_delete_all_my_sessions, 204)
      nil
    end

    private

    def session_query(page:, limit:, options:)
      unknown = options.keys - SESSION_OPTIONS
      raise ArgumentError, "unknown keyword: #{unknown.first}" unless unknown.empty?

      { page:, limit:, **options }.compact
    end

    def session_page_attributes(payload, sessions)
      {
        sessions:, total: payload['total'], page: payload['page'],
        limit: payload['limit'], total_pages: payload['total_pages'],
        has_more: payload['has_more'], next_cursor: payload['next_cursor'],
        prev_cursor: payload['prev_cursor']
      }
    end

    def record_current_sessions(sessions)
      current_ids = sessions.filter_map { |session| session.id if session.is_current }
      @current_device_session_ids = (@current_device_session_ids | current_ids).freeze
    end

    def auth_sessions(payload)
      array(payload['sessions'] || payload['data']).map do |session|
        build_auth_session(mapping(session))
      end
    end
  end
  private_constant :AuthSessions
end
