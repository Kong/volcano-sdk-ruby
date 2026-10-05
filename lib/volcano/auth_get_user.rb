# frozen_string_literal: true

module Volcano
  # Current-user requests and session cache updates.
  module AuthProfile
    include AuthProfileFields

    def user
      profile_request { ->(token) { get_user_response(token) } }
    end

    alias get_user user

    private

    def profile_request
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      request = yield
      payload = Transport.body(session_request(binding: binding, &request), 200)
      cache_current_user(payload, owned_session_binding(binding).first)
    end

    def cache_current_user(payload, generation)
      profile = profile_user_payload(payload)
      user = build_user(profile)
      raise Error::SessionChangedError unless @client.update_session_user_if_current?(profile, generation)

      user
    end

    def get_user_response(access_token)
      Transport.invoke do
        @transport.auth_get_user(authorization: access_token)
      end
    end

    def build_user(payload)
      new_profile_user(user_identity(payload), user_optional_attributes(payload), user_timestamps(payload))
    rescue ArgumentError => e
      raise Error::AuthenticationError, INVALID_USER, cause: e
    end

    def new_profile_user(identity, optional, timestamps)
      User.new(
        id: identity[:id], email: identity[:email], status: identity[:status],
        project_id: optional[:project_id], email_confirmed: optional[:email_confirmed],
        user_metadata: optional[:user_metadata], app_metadata: optional[:app_metadata],
        avatar_url: optional[:avatar_url], banned_until: timestamps[:banned_until],
        last_sign_in_at: timestamps[:last_sign_in_at], created_at: timestamps[:created_at],
        updated_at: timestamps[:updated_at]
      )
    end

    def user_identity(payload)
      {
        id: profile_required_id(payload['id']),
        email: profile_required_string(payload['email']),
        status: profile_status(payload['status'])
      }
    end

    def user_optional_attributes(payload)
      {
        project_id: profile_optional_string(payload['project_id']),
        email_confirmed: profile_optional_boolean(payload['email_confirmed']),
        user_metadata: profile_optional_object(payload['user_metadata']),
        app_metadata: profile_optional_object(payload['app_metadata']),
        avatar_url: profile_optional_string(payload['avatar_url'])
      }
    end

    def user_timestamps(payload)
      {
        banned_until: profile_parse_time(payload['banned_until']),
        last_sign_in_at: profile_parse_time(payload['last_sign_in_at']),
        created_at: profile_parse_time(payload['created_at']),
        updated_at: profile_parse_time(payload['updated_at'])
      }
    end
  end
end
