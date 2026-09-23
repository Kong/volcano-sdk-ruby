# frozen_string_literal: true

require 'volcano'

# @type method linked_provider: (Volcano::Auth) -> Volcano::LinkedOAuthProvider?
def linked_provider(auth)
  auth.list_linked_oauth_providers.first
end

# @type method provider_authorization: (Volcano::Auth) -> String
def provider_authorization(auth)
  auth.link_oauth_provider('github')
end

# @type method provider_token: (Volcano::Auth) -> Volcano::OAuthProviderTokenStatus
def provider_token(auth)
  auth.refresh_oauth_provider_token('github')
end

# @type method oauth_sign_in: (Volcano::Auth) -> Volcano::Session
def oauth_sign_in(auth)
  auth.sign_in_with_oauth('github', redirect_to: 'https://app.test/callback', state: 'nonce')
  auth.exchange_oauth_code(
    code: 'code', redirect_to: 'https://app.test/callback', state: 'nonce', expected_state: 'nonce'
  )
end

# @type method hosted_sign_in: (Volcano::Auth, Volcano::Session) -> Volcano::Session
def hosted_sign_in(auth, session)
  auth.get_hosted_auth_url(project_id: 'project', state: 'nonce')
  auth.adopt_hosted_auth_session(session, state: 'nonce', expected_state: 'nonce')
end

# @type method provider_api_data: (Volcano::Auth) -> Object?
def provider_api_data(auth)
  auth.call_oauth_api('github', endpoint: '/user', method: 'GET')
end
