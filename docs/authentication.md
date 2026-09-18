---
title: Authentication
description: Manage Volcano user accounts, sessions, email flows, and OAuth from Ruby.
order: 2
---

Sign in with a project's anonymous key and an existing user's credentials.
Enable the required [authentication methods](/platform/authentication/configuring-auth-methods) for the project first.
Install the SDK using the [quickstart](./README.md).

```ruby
require "volcano"

client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev")
)
session = client.auth.sign_in(
  email: ENV.fetch("VOLCANO_USER_EMAIL"),
  password: ENV.fetch("VOLCANO_USER_PASSWORD")
)
user = client.auth.user
raise "wrong user" unless user.id == session.user_id
puts user.email
```

Use a separate client for each independent user session.
The examples below describe separate account workflows using this client.
Keep access and refresh tokens out of logs; the SDK stores sessions in memory only.

## Sign up

```ruby
result = client.auth.sign_up(
  email: "new-user@example.com",
  password: "correct-horse-battery-staple",
  metadata: { display_name: "New User" }
)
puts result.message if result.confirmation_required
```

`sign_up` returns an immutable acknowledgement without changing the session by
default. The signup acknowledgement is identical for new and existing email
addresses. Pass `sign_in_when_allowed: true` to follow it with `sign_in` only when
confirmation is not required:

```ruby
result = client.auth.sign_up(email: "new-user@example.com", password: "correct-horse-battery-staple", sign_in_when_allowed: true)
session = result.session # nil when no follow-up sign-in ran.
```

A successful follow-up stores the session and emits the normal sign-in event.
A failed follow-up raises its usual typed error; it does not undo the successful signup.

## Sign in

```ruby
session = client.auth.sign_in(email: "user@example.com", password: "correct-horse-battery-staple")
current_session = client.auth.current_session
raise "session changed" unless current_session == session
```

`current_session` reads immutable local state. It does not refresh or validate
the token.

Sessions returned by authentication retain the user payload in `session.user`,
including metadata. The snapshot is deeply immutable and available without a
request. It is cached data, not proof of authentication; use `auth.user` to fetch
the server-validated profile. Existing three-field `Session` construction still
works, with `user: nil`. An adopted snapshot must have the same user ID.
Snapshots contain deeply frozen JSON data. Plain `Time` timestamps become UTC
ISO8601 strings with nanosecond precision; symbols become strings. Custom objects,
container/string/time subclasses, non-finite numbers, duplicate JSON keys, and
structures deeper than 100 levels raise `TypeError`. Use the typed `auth.user`
profile when you need Ruby `Time` values. Successful `user`, `update_user`,
`convert_anonymous`, and `confirm_email_change` calls update this snapshot
without changing credentials or emitting an authentication-state event unless an HTTP 401
requires automatic refresh. Successful recovery rotates credentials and emits `:token_refreshed`.
Previously returned sessions remain unchanged.

## Get the current user

```ruby
user = client.auth.user
raise "wrong user" unless user.id == session.user_id
```

`user` sends the active access token to Volcano and returns an immutable,
server-validated `Volcano::User`. The SDK recursively freezes its strings and
metadata and updates `current_session.user`. A session change while the request
is in flight raises
`Volcano::Error::SessionChangedError` instead of returning a stale profile.
`get_user` is available as a cross-SDK alias.

## Update the current user

```ruby
user = client.auth.update_user(
  password: "new-correct-horse-battery-staple",
  metadata: { display_name: "Grace", avatar: nil }
)
raise "wrong user" unless user.id == session.user_id
```

`update_user` changes the current user's password, metadata, or both. Metadata
is a shallow patch: omitted keys remain unchanged, and a `nil` value removes
that key. The method returns an immutable `Volcano::User` and updates the local
user snapshot. It rejects a response if another authentication operation
replaces the session while the request is in flight.

## Request a password reset email

```ruby
client.auth.reset_password_for_email(email: "user@example.com")
```

When transactional email is configured, Volcano sends the reset link. Success
returns `nil`, and the acknowledgement is intentionally identical whether or
not the email belongs to an account. Failures raise the same typed Volcano
errors as other authentication operations, and the current session remains
unchanged.

## Confirm an email address

```ruby
client.auth.confirm_email(token: "confirmation-token")
```

Success returns `nil`. Confirmation does not sign in the confirmed account or
change an unrelated local session.

## Resend a confirmation email

```ruby
client.auth.resend_confirmation(email: "user@example.com")
```

Success returns `nil` whether the account is unknown, already confirmed, or
eligible. Volcano sends mail only for an existing unconfirmed account when
transactional email is configured. Rate limits raise
`Volcano::Error::RateLimitedError` with `retry_after` when supplied.

## Request an email change

```ruby
result = client.auth.request_email_change(new_email: "new@example.com")
puts result.new_email
```

The immutable result contains the server acknowledgement. Its `message` and
`new_email` fields may be `nil`. The request requires an active session and
rejects a response if that session changes in flight.

## Cancel an email change

```ruby
client.auth.cancel_email_change
```

Success returns `nil` and preserves the active session. A successful stale
response is rejected if another authentication operation replaces the session
while cancellation is in flight.

## Confirm an email change

```ruby
user = client.auth.confirm_email_change(token: "email-change-token")
puts user.email
```

The method returns the immutable updated user and updates the local user
snapshot. A successful stale response is rejected if another authentication
operation replaces that session in flight.

## List sessions

```ruby
page = client.auth.list_sessions(page: 1, limit: 20)
page.sessions.each do |session|
  puts [session.id, session.user_agent, session.is_current].join(' ')
end
```

The method returns immutable `Volcano::SessionPage` and `Volcano::AuthSession`
values in activity order. It raises `Volcano::Error::SessionChangedError` instead
of returning a page for a session that was replaced while the request was in
flight. Sort, filter, and cursor controls are not yet exposed by this facade.

## Build a hosted-auth URL

```ruby
require 'securerandom'

hosted_state = SecureRandom.urlsafe_base64(32)
hosted_url = client.auth.get_hosted_auth_url(
  project_id: '00000000-0000-4000-8000-000000000020',
  action: 'signup',
  state: hosted_state
)
```

Store `hosted_state` in the user's signed server-side session before redirecting
to `hosted_url`. In the callback, atomically fetch and delete the stored state before validation,
even if validation or adoption fails. Reject a missing or already-consumed state.
After parsing the returned fragment into a `Volcano::Session`, validate and adopt it:

```ruby
session = client.auth.adopt_hosted_auth_session(
  returned_session,
  state: returned_state,
  expected_state: hosted_state
)
```

The SDK rejects a mismatched state before changing local authentication. It
does not parse browser URLs, navigate, or persist state.

The `action` deep link applies to Volcano's built-in page. A customized login
page receives the request but must implement its own signup or forgot-password
flow because Hosting ignores `action` for custom pages.

## Sign in with OAuth

```ruby
require 'securerandom'

oauth_state = SecureRandom.urlsafe_base64(32)
authorization_url = client.auth.sign_in_with_oauth(
  'github',
  redirect_to: 'https://app.example.com/auth/callback',
  state: oauth_state
)
```

Store `oauth_state` in the user's signed server-side session, then redirect the
user to the returned URL. In the callback, atomically fetch and delete the stored nonce as `stored_oauth_state`;
reject a missing or already-consumed nonce. Pass the returned and consumed states to
the SDK so it rejects login CSRF before exchanging the one-time code:

```ruby
session = client.auth.exchange_oauth_code(
  code: callback_code,
  redirect_to: 'https://app.example.com/auth/callback',
  state: callback_state,
  expected_state: stored_oauth_state
)
```

The callback URL must exactly match a registered project redirect. The exchange
stores the returned Volcano session on the client. The SDK does not open a
browser or persist OAuth state between requests; use your framework's signed
session or equivalent storage for that state.

## List linked OAuth providers

```ruby
client.auth.list_linked_oauth_providers.each do |provider|
  puts [provider.provider, provider.linked_at].join(' ')
end
```

The method returns a frozen array of immutable `Volcano::LinkedOAuthProvider`
values. It raises `Volcano::Error::SessionChangedError` if the active session
changes while the request is in flight.

## Link an OAuth provider

```ruby
authorization_url = client.auth.link_oauth_provider('github')
```

Redirect the user to the returned URL to complete the provider flow. The method
accepts `apple`, `github`, `google`, or `microsoft` and raises
`Volcano::Error::SessionChangedError` if the active session changes while the
request is in flight.

## Unlink an OAuth provider

```ruby
client.auth.unlink_oauth_provider('github')
```

The server rejects removal of the account's only authentication method. A
successful stale response raises `Volcano::Error::SessionChangedError` instead
of acknowledging work authorized by a replaced session.

## Check provider token status

```ruby
status = client.auth.get_oauth_provider_token('github')
puts [status.provider, status.expires_in].join(' ')
```

The immutable `Volcano::OAuthProviderTokenStatus` contains provider and expiry
metadata, not the credential. Volcano refreshes an expired token on the server.
A stale result raises `Volcano::Error::SessionChangedError`.

Refresh a provider token explicitly:

```ruby
status = client.auth.refresh_oauth_provider_token('github')
puts [status.provider, status.expires_in].join(' ')
```

The refresh credential and new access token remain on the server. A stale result
raises `Volcano::Error::SessionChangedError`.

Call a provider API through Volcano's fixed-host server proxy:

```ruby
repos = client.auth.call_oauth_api('github', endpoint: '/user/repos')
puts repos.first.fetch('name')
```

The method returns an immutable copy of the provider's JSON value. Volcano owns
token refresh and host validation. A stale result raises
`Volcano::Error::SessionChangedError`.

## Sign out all other devices

```ruby
client.auth.delete_all_other_sessions
```

Success returns `nil` and keeps the authorizing session active. Do not replace
the client's session while this request is in flight: the server may revoke that
replacement as an "other" session. If replacement occurs, the method raises
`Volcano::Error::SessionChangedError` instead of acknowledging a stale result.

## Revoke one session

```ruby
client.auth.delete_session('00000000-0000-4000-8000-000000000099')
```

The request uses the current access token. When its JWT contains a readable UUID `session_id`,
deleting that session clears local credentials even if the request outcome is uncertain.
Without that identifier, the SDK cannot recognize self-deletion. Deleting another session does not
itself clear local state. HTTP 401 recovery can rotate credentials and emit `:token_refreshed`;
a server-rejected refresh clears the captured session before the operation raises. If another authentication operation
replaces the session before deletion finishes, the method raises
`Volcano::Error::SessionChangedError` instead of clearing the replacement or
acknowledging a stale result.

## Sign in anonymously

```ruby
session = client.auth.sign_in_anonymously(metadata: { device: "mobile" })
```

Anonymous sign-ins must be enabled for the project. Convert the account before
signing out if the user needs to recover it later.

Attach email credentials while preserving the anonymous user's ID:

```ruby
user = client.auth.convert_anonymous(
  email: "user@example.com",
  password: "a-long-example-password-2026",
  metadata: { display_name: "Ada" }
)
```

When email confirmation is required, confirm the new address before treating it
as verified.

## Reset the password

```ruby
client.auth.reset_password(token: "recovery-token", new_password: "new-correct-horse-battery-staple")
```

Success returns `nil`. The reset revokes the recovered account's existing
sessions and does not sign it in. The client keeps any unrelated local session
unchanged; sign in with the new password when the reset flow completes.

## Start with a supplied access token

Pass `access_token` to `Volcano::Client.new` to start without a refresh token or
known user identity. Construction makes no request and leaves `refresh_token`,
`user_id`, and `user` as `nil`. `auth.user` validates and caches the profile
without changing credentials. Without a refresh token, `refresh_session` raises
`Volcano::Error::AuthenticationError`. `sign_out` clears local state and revokes the server
session when the access JWT contains a readable UUID `session_id`. Supplied credentials require both a refresh token and an access JWT with a readable UUID
`session_id` to enable refresh.
See the [token bootstrap example](./README.md#use-a-supplied-access-token).

## Adopt an existing session

```ruby
session = source.auth.current_session
fresh.auth.current_session = session if session
```

The writer copies and freezes a complete native session in memory only. It does
not make a request, persist credentials, or notify auth-state subscribers. It
raises `ArgumentError` for an incomplete value.

Password sign-in raises `Volcano::Error::SessionChangedError` if local session
state changes while the request is in flight. The late response does not replace
the newer state or emit a sign-in notification.

## Refresh the current session

```ruby
refreshed = client.auth.refresh_session
raise "refresh failed" unless client.auth.current_session.equal?(refreshed)
```

On success, `refresh_session` replaces the in-memory session and returns the
immutable new snapshot. An authentication rejection from the refresh endpoint clears the captured session.
Missing refresh credentials, failed session-continuity checks, server errors, and
transport failures preserve it, and a late
response never replaces a newer session. The SDK does not persist sessions.

## Observe auth-state changes

```ruby
subscription = client.auth.on_auth_state_change do |event, session|
  puts "#{event}: #{session ? 'authenticated' : 'anonymous'}"
end

# Later, stop receiving events.
subscription.unsubscribe
```

Registration immediately yields `:initial_session`. Successful session
creation, refresh, and local clearing yield `:signed_in`, `:token_refreshed`,
and `:signed_out`. Callbacks are delivered locally in transition order after the
state lock is released. Callback `StandardError` failures are isolated; exceptions such as
`Interrupt` propagate after the session transition has committed.
The SDK does not broadcast between processes or persist sessions.

## Sign out the current session

```ruby
client.auth.sign_out
raise "still signed in" if client.auth.current_session
```

Sign-out uses the refresh token directly when the SDK received both credentials together from
sign-in or a validated refresh. Supplied credentials use the access-token session when its JWT
contains a readable UUID `session_id`; on HTTP 401, the SDK can refresh once and revoke that
same session without adopting the renewed credentials. Without that identifier, sign-out uses
the supplied refresh token, or only clears local state if no refresh token is available.
It revokes the captured session and clears the captured in-memory
session. It succeeds without a request when no session exists. If revocation
fails, the SDK still clears that session and raises the typed error. Sign-out waits for an already-running refresh and uses its validated credentials.
Later refresh attempts raise `Volcano::Error::SessionChangedError` without a request.
Concurrent sign-out calls share one result. A separate sign-in or adoption remains current.
