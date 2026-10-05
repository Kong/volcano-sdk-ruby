# frozen_string_literal: true

# @type method invalid_oauth_calls: (Volcano::Auth, Volcano::Session) -> void
def invalid_oauth_calls(auth, session)
  auth.link_oauth_provider(12)
  auth.refresh_oauth_provider_token(:github)
  auth.call_oauth_api('github', endpoint: 42)
  auth.exchange_oauth_code(code: 'code', redirect_to: 'url', state: 'nonce')
  auth.adopt_hosted_auth_session('session', state: 'nonce', expected_state: 'nonce')
  auth.get_hosted_auth_url(project_id: session, state: 'nonce')
end
