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
      session ? yield(session.access_token) : response
    end

    private

    def retry_session(binding)
      refresh_captured_session(binding)
    rescue Error::SessionChangedError
      raise
    rescue Error::VolcanoError
      nil
    end

    def refresh_captured_session(binding)
      @refresh_lock.synchronize do
        generation, lineage, current = binding
        active_generation, = owned_session_binding(lineage)
        perform_refresh(generation, current) if active_generation == generation
        owned_session_binding(lineage).last
      end
    end

    def owned_session_binding(lineage)
      generation, active_lineage, current = @client.capture_session_binding
      raise Error::SessionChangedError unless current && active_lineage == lineage

      [generation, current]
    end

    def perform_refresh(generation, current)
      session = build_session(refresh_payload(current.refresh_token, generation))
      stored = @client.store_session_if_current?(session, generation, event: :token_refreshed)
      raise Error::SessionChangedError unless stored
    end

    def refresh_response(refresh_token)
      Transport.invoke do
        @transport.auth_refresh(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def refresh_payload(refresh_token, generation)
      Transport.body(refresh_response(refresh_token), 200)
    rescue Error::AuthenticationError
      @client.clear_session_if_current?(generation)
      raise
    end
  end
end
