# Volcano Ruby SDK

Official Ruby SDK for Volcano. This repository is a private proof of concept;
the gem is not published yet.

## Proof-of-concept API

Create a client with the project URL and anonymous key from Volcano:

```ruby
require "volcano"

client = Volcano::Client.new(
  api_url: "https://api.volcano.dev",
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  service_key: ENV["VOLCANO_SERVICE_KEY"]
)
```

The REST facade is synchronous. Successful calls return Volcano-owned values;
failures raise typed errors under `Volcano::Error`.

### Sign up

```ruby
result = client.auth.sign_up(
  email: "new-user@example.com",
  password: "secret",
  metadata: { display_name: "New User" }
)
puts result.message if result.confirmation_required
```

`sign_up` returns an immutable acknowledgement and never creates or replaces a
session. The response is identical for new and existing email addresses. Call
`sign_in` separately after the account is ready to establish a session.

### Sign in

```ruby
session = client.auth.sign_in(email: "user@example.com", password: "secret")
current_session = client.auth.current_session
raise "session changed" unless current_session == session
```

`current_session` reads immutable local state. It does not refresh or validate
the token.

### Get the current user

```ruby
user = client.auth.user
raise "wrong user" unless user.id == session.user_id
```

`user` sends the active access token to Volcano and returns an immutable,
server-validated `Volcano::User`. The SDK recursively freezes its strings and
metadata, but does not cache the profile or replace the session. A session
change while the request is in flight raises
`Volcano::Error::SessionChangedError` instead of returning a stale profile.
`get_user` is available as a cross-SDK alias.

### Update the current user

```ruby
user = client.auth.update_user(
  password: "new-secret",
  metadata: { display_name: "Grace", avatar: nil }
)
raise "wrong user" unless user.id == session.user_id
```

`update_user` changes the current user's password, metadata, or both. Metadata
is a shallow patch: omitted keys remain unchanged, and a `nil` value removes
that key. The method returns an immutable `Volcano::User` without replacing the
active session. It rejects a response if another authentication operation
replaces the session while the request is in flight.

### Request a password reset email

```ruby
client.auth.reset_password_for_email(email: "user@example.com")
```

When transactional email is configured, Volcano sends the reset link. Success
returns `nil`, and the acknowledgement is intentionally identical whether or
not the email belongs to an account. Failures raise the same typed Volcano
errors as other authentication operations, and the current session remains
unchanged.

### Confirm an email address

```ruby
client.auth.confirm_email(token: "confirmation-token")
```

Success returns `nil`. Confirmation does not sign in the confirmed account or
change an unrelated local session.

### Resend a confirmation email

```ruby
client.auth.resend_confirmation(email: "user@example.com")
```

Success returns `nil` whether the account is unknown, already confirmed, or
eligible. Volcano sends mail only for an existing unconfirmed account when
transactional email is configured. Rate limits raise
`Volcano::Error::RateLimitedError` with `retry_after` when supplied.

### Sign in anonymously

```ruby
session = client.auth.sign_in_anonymously(metadata: { device: "mobile" })
```

Anonymous sign-ins must be enabled for the project. Convert the account before
signing out if the user needs to recover it later.

Attach email credentials without changing the anonymous user's ID or current
session:

```ruby
user = client.auth.convert_anonymous(
  email: "user@example.com",
  password: "secure-password",
  metadata: { display_name: "Ada" }
)
```

When email confirmation is required, confirm the new address before treating it
as verified.

### Reset the password

```ruby
client.auth.reset_password(token: "recovery-token", new_password: "new-secret")
```

Success returns `nil`. The reset revokes the recovered account's existing
sessions and does not sign it in. The client keeps any unrelated local session
unchanged; sign in with the new password when the reset flow completes.

### Adopt an existing session

```ruby
session = source.auth.current_session
fresh.auth.current_session = session if session
```

The writer copies and freezes a complete native session in memory only. It does
not make a request or persist credentials, and raises `ArgumentError` for an
incomplete value.

### Refresh the current session

```ruby
refreshed = client.auth.refresh_session
raise "refresh failed" unless client.auth.current_session.equal?(refreshed)
```

On success, `refresh_session` replaces the in-memory session and returns the
immutable new snapshot. An authentication failure clears the session that
initiated the request. Server and transport failures preserve it, and a late
response never replaces a newer session. The SDK does not persist sessions.

### Sign out the current session

```ruby
client.auth.sign_out
raise "still signed in" if client.auth.current_session
```

`sign_out` revokes the current refresh token and clears the captured in-memory
session. It succeeds without a request when no session exists. If revocation
fails, the SDK still clears that session and raises the typed error. A session
established while sign-out is pending remains current.

### Query a database

```ruby
rows = client.database("main").from("items").select("*").eq("slug", "a").execute
```

### Upload and download an object

```ruby
client.storage.from("assets").upload("a.txt", "hello".b)
bytes = client.storage.from("assets").download("a.txt")
```

Uploads accept a binary `String` or an `IO`. Downloads return a binary
`String`.

### Acquire and release a lock

```ruby
lease = client.locks.acquire("build", ttl: 30)
client.locks.release("build", lease)
```

### Broadcast over realtime

Realtime calls are asynchronous and must run in an Async reactor:

```ruby
Async do
  channel = client.realtime.channel("deployments")
  channel.on("message") { |message| puts message.fetch("value") }
  channel.subscribe
  channel.send(event: "message", value: "contract")
  channel.unsubscribe
  client.realtime.disconnect
end.wait
```

This proof of concept implements connect, subscribe, publish, unsubscribe, and
clean shutdown. Reconnect, recovery, presence, and database-change
subscriptions are out of scope.

## Generated boundary

The internal REST transport is generated from the self-contained public
Volcano OpenAPI bundle at hosting commit
`a3f4a6e9d0fb48a16621383bd796d8b0d1378630`. Its SHA-256 is
`c26ab2f32961699b19f710c1174906b7baae077eefcec299a6c19a36d2f559f6`.
Generation uses `@openapitools/openapi-generator-cli` 2.41.0 with OpenAPI
Generator 7.17.0. Node is used only to regenerate the committed client and is
not a gem runtime dependency.

Run `npm ci && bin/check-openapi` to verify generated provenance. Use
`bundle exec rubocop -A` to apply safe formatting and lint fixes. Before
changing the facade, run `bundle exec rubocop --parallel`, `bundle exec rspec`,
and the shared Cucumber contract suite.
