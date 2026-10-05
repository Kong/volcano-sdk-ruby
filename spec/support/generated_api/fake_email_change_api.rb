# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    module FakeEmailChangeApi
      attr_accessor :confirmed_email_change_body

      def auth_cancel_email_change_with_http_info(options = {})
        (@cancel_email_change_calls ||= []) << options
        [FakeGeneratedModel.new({}), 200, {}]
      end

      def cancel_email_change_calls
        @cancel_email_change_calls || []
      end

      def auth_confirm_email_change_with_http_info(body, options = {})
        (@confirm_email_change_calls ||= []) << [body, options]
        profile = { user: { id: 'user-123', email: 'new@example.com', status: 'active' } }
        [@confirmed_email_change_body || JSON.generate(profile), 200, {}]
      end

      def confirm_email_change_calls
        @confirm_email_change_calls || []
      end

      def auth_delete_all_my_sessions_with_http_info
        @delete_other_sessions_calls = true
        [nil, 204, {}]
      end

      def auth_delete_my_session_with_http_info(session_id)
        @deleted_session_id = session_id
        [nil, 204, {}]
      end

      def auth_get_my_sessions_with_http_info(options = {})
        @list_sessions_options = options
        page = {
          sessions: [], total: 21, page: 2, limit: 10, total_pages: 3
        }
        [FakeGeneratedModel.new(page), 200, {}]
      end

      def delete_other_sessions_called?
        @delete_other_sessions_calls || false
      end

      attr_reader :deleted_session_id, :list_sessions_options
    end
  end
end
