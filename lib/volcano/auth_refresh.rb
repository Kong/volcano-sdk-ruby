# frozen_string_literal: true

module Volcano
  # Refreshes only the session captured by the initiating operation.
  class Auth
    def refresh_session
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      refresh_captured_session(binding)
    end

    def session_read
      binding = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' unless binding.last

      response = yield(binding.last.access_token)
      return response unless response.status == 401

      session = retry_session(binding)
      return response unless session

      token = owned_session_binding(binding).last.access_token
      response = yield(token)
      owned_session_binding(binding)
      response
    end

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
      @refresh_lock.synchronize do
        active_generation, = owned_session_binding(binding)
        perform_refresh(binding, notifications) if active_generation == binding.first
      end
    ensure
      # Only the dispatcher owner drains, after refresh coordination is released.
      notifications.each(&:call)
    end

    def owned_session_binding(binding)
      active = @client.capture_session_binding
      raise Error::AuthenticationError, 'No active session' if rejected_refresh?(binding, active)

      generation, active_lineage, current = active
      raise Error::SessionChangedError unless current && active_lineage == binding[1]

      [generation, current]
    end

    def rejected_refresh?(binding, active)
      generation, lineage, = binding
      @rejected_refresh == [generation, lineage] &&
        active == [generation + 1, lineage + 1, nil]
    end

    def perform_refresh(binding, notifications)
      session = refreshed_session(binding, notifications)
      stored = @client.store_session_if_current?(
        session, binding.first, event: :token_refreshed, notifications: notifications
      )
      raise Error::SessionChangedError unless stored
    end

    def refreshed_session(binding, notifications)
      owned_complete_session(build_session(refresh_payload(binding, notifications)))
    rescue KeyError, TypeError, NoMethodError, ArgumentError => e
      raise Error::TransportError, INCOMPLETE_SESSION, cause: e
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
      generation, lineage, = binding
      cleared = @client.clear_session_if_current?(generation, notifications: notifications)
      raise Error::SessionChangedError unless cleared

      @rejected_refresh = [generation, lineage]
      raise
    rescue Error::VolcanoError
      owned_session_binding(binding)
      raise
    end
  end
end
