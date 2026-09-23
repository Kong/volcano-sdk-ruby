# frozen_string_literal: true

module SpecSupport
  module GeneratedAPI
    class FakeLocksApi
      attr_reader :calls

      def initialize
        @calls = []
      end

      def acquire_project_lock_with_http_info(key, token, request_id, body, options = {})
        @calls << [:acquire, key, token, request_id, body, options]
        [FakeGeneratedModel.new(expires_at: Time.iso8601('2026-08-26T12:00:30Z'), fencing_token: 7), 201, {}]
      end

      def release_project_lock_with_http_info(key, token, request_id)
        @calls << [:release, key, token, request_id]
        [nil, 204, {}]
      end

      def get_project_lock_with_http_info(key, request_id, options = {})
        @calls << [:get, key, request_id, options]
        state = FakeGeneratedModel.new(
          held: true,
          expires_at: Time.iso8601('2026-08-26T12:00:30Z'),
          fencing_token: 7
        )
        [state, 200, {}]
      end

      def renew_project_lock_with_http_info(key, token, request_id, body, options = {})
        @calls << [:renew, key, token, request_id, body, options]
        lease = FakeGeneratedModel.new(
          expires_at: Time.iso8601('2026-08-26T12:01:00Z'),
          fencing_token: 7
        )
        [lease, 200, {}]
      end

      def force_release_project_lock_with_http_info(key, request_id)
        @calls << [:force_release, key, request_id]
        [nil, 204, {}]
      end
    end
  end
end
