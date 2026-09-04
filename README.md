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

### Request an email change

```ruby
result = client.auth.request_email_change(new_email: "new@example.com")
puts result.new_email
```

The immutable result contains the server acknowledgement. Its `message` and
`new_email` fields may be `nil`. The request requires an active session and
rejects a response if that session changes in flight.

### Cancel an email change

```ruby
client.auth.cancel_email_change
```

Success returns `nil` and preserves the active session. A successful stale
response is rejected if another authentication operation replaces the session
while cancellation is in flight.

### Confirm an email change

```ruby
user = client.auth.confirm_email_change(token: "email-change-token")
puts user.email
```

The method returns the immutable updated user without replacing the active
session. A successful stale response is rejected if another authentication
operation replaces that session in flight.

### List sessions

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

### Build a hosted-auth URL

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
to `hosted_url`. After parsing the returned fragment into a `Volcano::Session`,
validate and adopt it atomically:

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

### Sign in with OAuth

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
user to the returned URL. In the callback, pass the returned and stored states
to the SDK so it rejects login CSRF before exchanging the one-time code:

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

### List linked OAuth providers

```ruby
client.auth.list_linked_oauth_providers.each do |provider|
  puts [provider.provider, provider.linked_at].join(' ')
end
```

The method returns a frozen array of immutable `Volcano::LinkedOAuthProvider`
values. It raises `Volcano::Error::SessionChangedError` if the active session
changes while the request is in flight.

### Link an OAuth provider

```ruby
authorization_url = client.auth.link_oauth_provider('github')
```

Redirect the user to the returned URL to complete the provider flow. The method
accepts `apple`, `github`, `google`, or `microsoft` and raises
`Volcano::Error::SessionChangedError` if the active session changes while the
request is in flight.

### Unlink an OAuth provider

```ruby
client.auth.unlink_oauth_provider('github')
```

The server rejects removal of the account's only authentication method. A
successful stale response raises `Volcano::Error::SessionChangedError` instead
of acknowledging work authorized by a replaced session.

### Check provider token status

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

### Sign out all other devices

```ruby
client.auth.delete_all_other_sessions
```

Success returns `nil` and keeps the authorizing session active. Do not replace
the client's session while this request is in flight: the server may revoke that
replacement as an "other" session. If replacement occurs, the method raises
`Volcano::Error::SessionChangedError` instead of acknowledging a stale result.

### Revoke one session

```ruby
client.auth.delete_session('00000000-0000-4000-8000-000000000099')
```

The request uses the current access token. Deleting that token's own session
clears local credentials, including when the request outcome is uncertain;
deleting another session preserves them. If another authentication operation
replaces the session before deletion finishes, the method raises
`Volcano::Error::SessionChangedError` instead of clearing the replacement or
acknowledging a stale result.

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

### Observe auth-state changes

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
state lock is released, and callback failures cannot interrupt auth operations.
The SDK does not broadcast between processes or persist sessions.

### Sign out the current session

```ruby
client.auth.sign_out
raise "still signed in" if client.auth.current_session
```

`sign_out` revokes the current refresh token and clears the captured in-memory
session. It succeeds without a request when no session exists. If revocation
fails, the SDK still clears that session and raises the typed error. A session
established while sign-out is pending remains current.

### Invoke a function

```ruby
result = client.functions.invoke(
  "send-welcome",
  { user_id: session.user_id }
)
puts [result.status, result.version, result.data]
```

`invoke` resolves a DNS-safe function name and sends a JSON object. It uses the
active user session when present, then a configured service key, then the
anonymous key. An anonymous key can invoke a public function without a user
session; the function receives no user identity. The immutable result includes
the response body, status, headers, and `X-Volcano-Version`. A function's own
non-2xx response is returned when the version header proves it ran; platform
failures raise typed SDK errors.

### Read project logs

```ruby
project_id = "00000000-0000-4000-8000-000000000001"
page = client.logs.search(
  project_id,
  { resource: { type: "function" }, limit: 100 }
)
page.data.each { |event| puts [event["timestamp"], event["body"]] }

activity = client.logs.activity(
  project_id,
  { resource: { type: "function" }, bucket_count: 24 }
)
puts activity.total
```

`search` returns an immutable page of retained runtime or deployment log
events. Pass `next_cursor` back as `cursor` to continue a search. `activity`
returns immutable time buckets using the same resource selector and query
syntax. Both methods require an active user session.

### Query a database

```ruby
rows = client.database("main").from("items").select("*").eq("slug", "a").execute
```

Database builders are immutable, so a base query can be reused safely. Chain
`neq`, `gt`, `gte`, `lt`, and `lte` for comparison filters:

```ruby
base_query = client.database("main").from("items").select("id", "priority")
rows = base_query
       .gte("priority", 3)
       .lt("priority", 10)
       .order("priority", ascending: false)
       .order("id")
       .limit(10)
       .offset(20)
       .execute

matching_rows = client.database("main")
                      .from("items")
                      .select("*")
                      .ilike("name", "%volcano%")
                      .is("deleted_at", nil)
                      .in("status", %w[draft published])
                      .execute

inserted_rows = client.database("main")
                      .from("items")
                      .insert(name: "Volcano", status: "draft")
                      .execute

updated_rows = client.database("main")
                     .from("items")
                     .update(status: "published")
                     .eq("name", "Volcano")
                     .execute

deleted_rows = client.database("main")
                     .from("items")
                     .delete
                     .eq("name", "Volcano")
                     .execute
```

Updates and deletes require at least one filter; Volcano rejects filterless mutations.

Use `database_connection_string` inside a Volcano function to select database
access without changing the advertised `DATABASE_URL` target:

```ruby
connection_string = Volcano.database_connection_string(
  ENV.fetch("DATABASE_URL"),
  user_id: event.dig("__volcano_auth", "user_id")
)
```

Pass a user ID to enforce that user's Row-Level Security policies. Omit
`user_id:` for full service access.
The helper preserves libpq connection syntax, including hostless and multi-host
targets, and leaves unrelated query values unchanged.

### Upload, download, and list objects

```ruby
bucket = client.storage.from("assets")
bucket.upload("a.txt", "hello".b)
bytes = bucket.download("a.txt")
first_kibibyte = bucket.download("archive.bin", range: "bytes=0-1023")
video = "demo video".b
uploaded = bucket.upload_resumable(
  "videos/automatic.mp4",
  video,
  content_type: "video/mp4",
  on_progress: ->(uploaded_bytes, total_bytes) { puts "#{uploaded_bytes}/#{total_bytes}" }
)
puts uploaded.name
upload_session = bucket.create_upload_session(
  "videos/demo.mp4",
  total_size: video.bytesize,
  content_type: "video/mp4",
  part_size: 8_388_608
)
puts [upload_session.session_id, upload_session.total_parts]
part = bucket.upload_part(
  "videos/demo.mp4",
  session_id: upload_session.session_id,
  part_number: 1,
  data: video
)
puts part.etag
status = bucket.get_upload_session(
  "videos/demo.mp4",
  session_id: upload_session.session_id
)
puts [status.parts_uploaded, status.bytes_uploaded]
completed = bucket.complete_upload_session(
  "videos/demo.mp4",
  session_id: upload_session.session_id
)
puts completed.name

page = bucket.list("avatars", limit: 100)
page.objects.each { |object| puts object.name }

next_page = bucket.list("avatars", limit: 100, cursor: page.next_cursor) if page.next_cursor

removed_paths = bucket.remove(["archive/a.txt", "archive/b.txt"])
moved = bucket.move("drafts/a.txt", "published/a.txt")
copied = bucket.copy("templates/a.txt", "drafts/a.txt")
public_object = bucket.update_visibility("avatars/a.png", public: true)
puts public_object.public_url
public_url = bucket.get_public_url("avatars/a.png")
puts public_url
```

Uploads accept a binary `String` or an `IO`. Downloads return a binary
`String`. Listing returns immutable object metadata and an optional cursor for
the next page. Removals run in input order; a failed request raises after any
earlier paths have already been deleted.
Pass an HTTP byte range to download only part of an object.
`create_upload_session` returns the immutable server-selected part size, part
count, and expiration time for a resumable upload.
`upload_resumable` creates a session, chunks the data using the server-selected
part size, and completes the upload. It streams seekable `IO` values directly;
non-seekable inputs are spooled to a temporary file with bounded reads. If a
part or progress callback fails, it makes a best-effort abort and raises the
original error. `on_progress` runs after each successful part with cumulative
uploaded bytes and the total size.
`upload_part` returns immutable part metadata and can safely retry the same part
number to replace that part.
`get_upload_session` returns immutable progress and uploaded-part metadata for
resuming an interrupted upload.
`complete_upload_session` assembles the uploaded parts and returns the stored
object.
`abort_upload_session(path, session_id: ...)` abandons a session and discards
its uploaded parts.
Visibility updates return the server-confirmed object; `public_url` is set only
when the object is public.
`get_public_url` constructs a URL locally and does not check object visibility.

### Inspect, acquire, and release a lock

```ruby
state = client.locks.get("build")
puts state.held
lease = client.locks.acquire("build", ttl: 30)
lease = client.locks.renew("build", lease, ttl: 30)
client.locks.release("build", lease)
client.locks.force_release("stale-build")

client.locks.with_lock("deploy", ttl: 30) do |guard|
  deploy(fencing_token: guard.lease.fencing_token)
  raise "lock lost" if guard.lost?
end
```

`locks.get` returns immutable lock availability, expiry, and fencing-token
state without acquiring the lock.
`locks.renew` returns a new immutable lease and leaves the previous value
unchanged.
`locks.with_lock` renews the lease for the lifetime of the block and always
attempts to release its latest lease. The guard exposes the latest immutable
lease, `lost?`, and `wait_lost(timeout:)`. Use the fencing token for protected
writes; stop work when the guard reports lease loss.
`locks.force_release` drops any current lease without an ownership token. Use
it only for administrative recovery behind fencing-token enforcement.

### Broadcast over realtime

Realtime calls are asynchronous and must run in an Async reactor:

```ruby
Async do
  stop_connect = client.realtime.on_connect do |context|
    puts "connected #{context.client}"
  end
  client.realtime.on_disconnect do |context|
    puts "disconnected #{context.reason}"
  end
  client.realtime.on_error { |context| warn context.message }

  channel = client.realtime.channel("deployments")
  raise "unexpected channel" unless channel.name == "broadcast:deployments"
  channel.on("message") { |message| puts message.fetch("value") }
  channel.subscribe
  raise "not connected" unless client.realtime.connected?
  channel.send(event: "message", value: "contract")
  client.realtime.remove_channel("deployments")
  raise "disconnected" unless client.realtime.connected?
  client.realtime.disconnect
  raise "still connected" if client.realtime.connected?
  stop_connect.call
end.wait
```

### Track presence

Presence identity and metadata come from the authenticated user. `track` keeps
optional application state locally without replacing that server-managed data:

```ruby
Async do
  lobby = client.realtime.channel("lobby", type: :presence)
  lobby.on_presence_sync do |state|
    puts "#{state.length} clients online"
  end
  lobby.on("join") { |info| puts "joined #{info.user}" }
  lobby.on("leave") { |info| puts "left #{info.user}" }

  lobby.subscribe
  lobby.track("status" => "online")
  puts lobby.tracked_state.fetch("status")
  lobby.presence_state.each_value { |info| puts info.data }
  lobby.unsubscribe
  client.realtime.disconnect
end.wait
```

`presence_state` returns an immutable snapshot keyed by Centrifuge client ID.
`get_presence_state` is an equivalent cross-SDK alias. Subscribe again to fetch
a fresh authoritative snapshot.

### Subscribe to Postgres changes

Postgres channels deliver immutable, RLS-scoped row changes and filter
callbacks by event, schema, and table. Configure the database once to expand
lightweight INSERT and UPDATE notifications into full rows before delivery:

```ruby
require "async/queue"

Async do
  received = Async::Queue.new
  client.realtime.database_name = "app"
  changes = client.realtime.channel("public:messages", type: :postgres)
  changes.on_postgres_changes("INSERT", schema: "public", table: "messages") do |change|
    received.enqueue(change)
  end
  changes.subscribe

  change = received.dequeue # Wait for an INSERT from another client.
  puts change.record.fetch("body")
  client.realtime.disconnect
end.wait
```

Auto-fetch is enabled by default and uses the authenticated session captured
for the subscription. Lookups for the same table that arrive within 20
milliseconds are grouped into one request, up to 50 rows. Deliveries remain
ordered, including repeated notifications for the same row. DELETE notifications
are expanded locally from `old_record` or `id`. If a lookup fails, the error
callback runs and the original lightweight change is delivered. Use
`auto_fetch: false` when creating the channel to receive lightweight
notifications without database requests. Set `fetch_batch_window_ms:` and
`fetch_max_batch_size:` on the channel to override the batching defaults. Both
values must be positive integers, and the maximum batch size cannot exceed 128.

`remove_channel` unsubscribes and forgets one channel. `remove_all_channels`
does the same for every managed channel without disconnecting the shared
realtime transport, so later calls to `channel` return fresh facades. Pass the
same `type:` to `remove_channel` for every non-broadcast channel. Unexpected
transport loss reconnects with bounded exponential backoff and restores active
subscriptions. Broadcast channels recover retained publications only for this
client lifetime and the same authenticated-user lineage. Recovery state is not
persisted across processes. Postgres channels do not recover missed
publications yet; presence channels rebuild their current snapshot.
Connection callbacks receive immutable contexts and run outside protocol
processing. Each registration returns an idempotent callable that stops future
delivery.

## Generated boundary

The internal REST transport is generated from `openapi/openapi.yaml`, which
matches the public bundle from [Hosting #991](https://github.com/Kong/volcano-hosting/pull/991)
at commit `ef03f689e`.
Its SHA-256 is `076d97809c95f50567d8b100f4188c1fe2b74e73a388e335c79850e66edfc0e4`.
Generation uses `@openapitools/openapi-generator-cli` 2.41.0 with OpenAPI
Generator 7.17.0. Node is used only to regenerate the committed client and is
not a gem runtime dependency.

Run `npm ci && bin/check-openapi` to verify generated provenance. Use
`bundle exec rubocop -A` to apply safe formatting and lint fixes. Before
changing the facade, run `bundle exec rubocop --parallel`, `bundle exec rspec`,
and the shared Cucumber contract suite.
