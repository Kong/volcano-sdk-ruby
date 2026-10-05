# frozen_string_literal: true

module Volcano
  # Refreshes only the session captured by the initiating operation.
  module AuthRefresh
    include AuthNotificationDispatch
    include AuthSessionBinding

    def refresh_session
      binding = @client.capture_session_binding
      session = binding.last
      raise Error::AuthenticationError, 'No active session' unless session

      refresh_captured_session([binding.first, binding[1], session])
    end

    def session_request(binding: @client.capture_session_binding)
      raise Error::AuthenticationError, 'No active session' unless binding.last

      binding = owned_session_binding(binding)
      response = yield(binding.last.access_token)
      return response unless response.status == 401

      session = retry_session(binding)
      return response unless session

      token = owned_session_binding(binding).last.access_token
      response = yield(token)
      owned_session_binding(binding)
      response
    end

    def session_read(...) = session_request(...)

    private

    def retry_session(binding)
      refresh_captured_session(binding)
    rescue Error::SessionChangedError
      raise
    rescue Error::VolcanoError
      validate_read_failure(binding)
      nil
    end

    def validate_read_failure(binding)
      owned_session_binding(binding)
    rescue Error::AuthenticationError
      nil
    end

    def refresh_captured_session(binding)
      refresh_with_notifications(binding)
      owned_session_binding(binding).last
    end

    def refresh_with_notifications(binding)
      # @type var notifications: Array[Method]
      notifications = []
      active_generation, = owned_session_binding(binding)
      binding[1].refresh { perform_refresh(binding, notifications) } if active_generation == binding.first
      raise Error::SessionChangedError if binding[1].closing?
    rescue Error::VolcanoError
      validate_read_failure(binding)
      raise
    ensure
      # Only the dispatcher owner drains, after refresh coordination is released.
      run_auth_notifications(notifications)
    end

    def perform_refresh(binding, notifications)
      active = owned_session_binding(binding)
      return active.last if active.first != binding.first

      refresh_token = binding.last.refresh_token
      raise Error::AuthenticationError, 'No refresh token' unless refresh_token

      session = refreshed_session(binding, refresh_token, notifications)
      unless binding[1].closing?
        @client.store_session_if_current?(
          session, binding.first, event: :token_refreshed, notifications: notifications
        )
      end
      session
    end

    def refreshed_session(binding, refresh_token, notifications)
      _, owner, current = binding
      verified = owner.verified_pair?(current)
      begin
        SessionCredentials.validate_refresh_source(current, verified: verified)
        owner.verify_pair(nil)
        parse_and_verify_refresh(owner, current, binding, refresh_token, notifications)
      rescue Error::RateLimitedError
        owner.verify_pair(current) if verified
        raise
      end
    end

    def parse_and_verify_refresh(owner, current, binding, refresh_token, notifications)
      session = parse_refresh_session(refresh_payload(binding, refresh_token, notifications))
      verify_refreshed_session(owner, current, session)
      session
    end

    def verify_refreshed_session(owner, current, session)
      SessionCredentials.validate_refresh(current, session)
      owner.verify_pair(session)
    end

    def refresh_payload(binding, refresh_token, notifications)
      Transport.body(refresh_response(refresh_token), 200)
    rescue Error::AuthenticationError
      generation, owner, = binding
      @client.reject_refresh_if_current?(generation, notifications: notifications) unless owner.closing?
      raise
    end
  end
end
