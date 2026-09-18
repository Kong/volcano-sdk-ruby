# frozen_string_literal: true

module Volcano
  # Revokes the captured server session and clears its local lineage.
  class Auth
    def sign_out
      binding = @client.capture_session_binding
      return unless binding.last

      notifications = []
      @refresh_lock.synchronize { sign_out_captured(binding, notifications) }
    ensure
      notifications&.each(&:call)
    end

    private

    def sign_out_captured(binding, notifications)
      generation, lineage, current = revocation_binding(binding)
      error = revocation_error(current)
      lineage = nil unless access_token_session_id(current.access_token)
      cleared = @client.clear_session_if_current?(generation, lineage: lineage, notifications: notifications)
      raise Error::SessionChangedError, cause: error unless cleared

      raise error if error
    end

    def revocation_binding(binding)
      active = @client.capture_session_binding
      active.last && active[1] == binding[1] ? active : binding
    end

    def logout_response(refresh_token)
      Transport.invoke do
        @transport.auth_logout(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def revocation_error(session)
      session_id = access_token_session_id(session.access_token)
      return revoke_access_session(session, session_id) if session_id
      return unless session.refresh_token

      Transport.body(logout_response(session.refresh_token), 204)
      nil
    rescue Error::VolcanoError => e
      e
    end

    def revoke_access_session(session, session_id)
      error = delete_session_error(session.access_token, session_id)
      return error unless error&.status == 401 && session.refresh_token

      refreshed = parse_refresh_session(Transport.body(refresh_response(session.refresh_token), 200))
      SessionCredentials.validate_refresh(session, refreshed)
      delete_session_error(refreshed.access_token, session_id)
    end
  end
end
