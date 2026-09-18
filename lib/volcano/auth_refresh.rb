# frozen_string_literal: true

module Volcano
  # Refreshes only the session captured by the initiating operation.
  class Auth
    def refresh_session
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      refresh_captured_session(binding)
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

    alias session_read session_request

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
      notifications = []
      active_generation, = owned_session_binding(binding)
      binding[1].refresh { perform_refresh(binding, notifications) } if active_generation == binding.first
      raise Error::SessionChangedError if binding[1].closing?
    rescue Error::VolcanoError
      validate_read_failure(binding)
      raise
    ensure
      # Only the dispatcher owner drains, after refresh coordination is released.
      notifications.each(&:call)
    end

    def owned_session_binding(binding)
      active = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' if rejected_refresh?(binding, active)

      _, active_lineage, current = active
      raise Error::SessionChangedError unless current && active_lineage == binding[1]

      active
    end

    def rejected_refresh?(binding, active)
      generation, lineage, = binding
      @rejected_refresh == [generation, lineage] &&
        active.first == generation + 1 && active.last.nil?
    end

    def perform_refresh(binding, notifications)
      active = owned_session_binding(binding)
      return active.last if active.first != binding.first
      raise Error::AuthenticationError, 'No refresh token' unless binding.last.refresh_token

      SessionCredentials.validate_refresh_source(binding.last)
      session = refreshed_session(binding, notifications)
      unless binding[1].closing?
        @client.store_session_if_current?(
          session, binding.first, event: :token_refreshed, notifications: notifications
        )
      end
      session
    end

    def refreshed_session(binding, notifications)
      owner = binding[1]
      owner.verify_pair(nil)
      session = parse_refresh_session(refresh_payload(binding, notifications))
      SessionCredentials.validate_refresh(binding.last, session)
      owner.verify_pair(session)
      session
    end

    def refresh_response(refresh_token)
      Transport.invoke do
        @transport.auth_refresh(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def refresh_payload(binding, notifications)
      Transport.body(refresh_response(binding.last.refresh_token), 200)
    rescue Error::AuthenticationError
      generation, owner, = binding
      if !owner.closing? && @client.clear_session_if_current?(generation, notifications: notifications)
        @rejected_refresh = [generation, owner]
      end
      raise
    end
  end
end
