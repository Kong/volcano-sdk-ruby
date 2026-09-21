# frozen_string_literal: true

module Volcano
  # Revokes the captured server session and clears its local lineage.
  class Auth
    def sign_out
      binding = @client.capture_session_binding
      return binding[1].wait_for_sign_out unless binding.last

      notifications = []
      binding[1].sign_out do |preceding, pending|
        sign_out_captured(binding, preceding, pending, notifications)
      end
    ensure
      notifications&.each(&:call)
    end

    private

    def sign_out_captured(binding, preceding, pending, notifications)
      generation, owner, = binding
      current, refresh_error = revocation_credentials(binding, preceding)
      error = revocation_error(current, owner, pending ? refresh_error : nil, joined: pending)
      cleared = @client.clear_session_if_current?(generation, lineage: owner, notifications: notifications)
      raise Error::SessionChangedError, cause: error unless cleared

      raise error if error
    end

    def revocation_credentials(binding, preceding)
      [binding[1].result(preceding) || binding.last, nil]
    rescue Error::VolcanoError => e
      [binding.last, e]
    end

    def logout_response(refresh_token)
      Transport.invoke do
        @transport.auth_logout(
          authorization: @client.anon_token,
          refresh_token: refresh_token
        )
      end
    end

    def revocation_error(session, owner, refresh_error, joined:)
      session_id = access_token_session_id(session.access_token)
      verified = owner.verified_pair?(session)
      return revoke_access_session(session, session_id, refresh_error, joined: joined) if session_id && !verified

      refresh_revocation_error(session, refresh_error, verified: verified)
    rescue Error::VolcanoError => e
      e
    end

    def refresh_revocation_error(session, refresh_error, verified:)
      return refresh_error if refresh_error && !verified

      revoke_refresh_session(session.refresh_token)
    end

    def revoke_refresh_session(refresh_token)
      return unless refresh_token

      Transport.body(logout_response(refresh_token), 204)
      nil
    end

    def revoke_access_session(session, session_id, refresh_error, joined:)
      error = delete_session_error(session.access_token, session_id)
      return error unless refreshable_revocation?(error, session)
      return refresh_error || error if joined

      refreshed = parse_refresh_session(Transport.body(refresh_response(session.refresh_token), 200))
      SessionCredentials.validate_refresh(session, refreshed)
      delete_session_error(refreshed.access_token, session_id)
    end

    def refreshable_revocation?(error, session)
      error&.status == 401 && session.refresh_token
    end
  end
end
