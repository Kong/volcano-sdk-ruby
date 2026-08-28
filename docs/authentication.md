# Authentication

Create a client with your project URL and anonymous key, then use `client.auth`
for account and session operations.

```ruby
require "volcano"

client = Volcano::Client.new(
  api_url: "https://api.volcano.dev",
  anon_key: ENV.fetch("VOLCANO_ANON_KEY")
)

session = client.auth.sign_in(
  email: "user@example.com",
  password: ENV.fetch("VOLCANO_USER_PASSWORD")
)

puts client.current_user.id
puts session.expires_in
```

The client keeps `current_user` and `current_session` in memory. Pass both
tokens when restoring an existing session in a new client. An access token
without a refresh token is valid, but a refresh token without an access token
is rejected.

```ruby
restored = Volcano::Client.new(
  api_url: "https://api.volcano.dev",
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  access_token: session.access_token,
  refresh_token: session.refresh_token
)

restored.auth.refresh_session
```

Store tokens in the secure storage provided by your runtime. Do not log them or
place them in source control.

## Manage the session

Subscribe to auth-state changes when application state must follow the client.
The block runs immediately with the current user and after committed auth
changes. Call the returned proc to unsubscribe.

```ruby
unsubscribe = client.auth.on_auth_state_change do |user|
  puts(user ? "signed in" : "signed out")
end

client.auth.refresh_session
client.auth.sign_out
unsubscribe.call
```

A failed refresh clears local authentication so stale credentials are not
reused. `sign_out` also clears local state if the remote revoke fails.

```ruby
page = client.auth.get_sessions(page: 1, limit: 20)
page.sessions.each { |device_session| puts device_session.id }

client.auth.delete_session(session_id: "session-id")
client.auth.delete_all_other_sessions
```

## Create and update accounts

Sign-up can return without a session when email confirmation is required.

```ruby
result = client.auth.sign_up(
  email: "new-user@example.com",
  password: ENV.fetch("VOLCANO_NEW_USER_PASSWORD"),
  user_metadata: { "plan" => "starter" }
)

puts "Check your email" if result.confirmation_required
```

Update the current user, or start with an anonymous account and preserve its
identity when converting it:

```ruby
client.auth.update_user(user_metadata: { "plan" => "pro" })

client.auth.sign_out
client.auth.sign_up_anonymous(user_metadata: { "source" => "demo" })
anonymous_id = client.current_user.id

converted = client.auth.convert_anonymous(
  email: "converted@example.com",
  password: ENV.fetch("VOLCANO_CONVERTED_USER_PASSWORD")
)
raise "identity changed" unless converted.id == anonymous_id
```

Conversion is permanent once the API accepts it. If the follow-up token rotation
fails, the method still returns the converted user and clears the local session;
sign in with the new credentials to continue.

Email workflows are explicit operations:

```ruby
client.auth.resend_confirmation(email: "new-user@example.com")
client.auth.confirm_email(token: confirmation_token)
client.auth.forgot_password(email: "user@example.com")
client.auth.reset_password(token: recovery_token, new_password: new_password)

change = client.auth.request_email_change(new_email: "next@example.com")
client.auth.confirm_email_change(token: email_change_token)
# Or cancel a pending request:
client.auth.cancel_email_change
```

## Open hosted auth and OAuth

Hosted auth returns a URL and generated state value for your application to
retain before navigation:

```ruby
request = client.auth.get_hosted_auth_url(
  project_id: "project-id",
  action: "login"
)
puts request.authorization_url
```

OAuth authorization follows the same pattern. Preserve `request.state` and
pass it as `expected_state` during exchange; the SDK rejects a mismatch before
calling the API.

```ruby
request = client.auth.get_oauth_authorization_url(
  provider: "github",
  redirect_url: "https://app.example.com/auth/callback"
)

# After the provider redirects to your application:
client.auth.exchange_oauth_code(
  code: authorization_code,
  redirect_url: "https://app.example.com/auth/callback",
  state: callback_state,
  expected_state: request.state
)
```

Signed-in users can link providers, inspect them, refresh provider tokens, and
call provider APIs through Volcano:

```ruby
link = client.auth.link_oauth_provider(
  provider: "github",
  redirect_url: "https://app.example.com/auth/link/callback"
)

providers = client.auth.get_linked_oauth_providers
token = client.auth.get_oauth_provider_token(provider: "github")
client.auth.refresh_oauth_token(provider: "github")
profile = client.auth.call_oauth_api(provider: "github", endpoint: "/user")
client.auth.unlink_oauth_provider(provider: "github")
```

Keep generated state values and provider tokens secret. Navigate to the returned
authorization URL only after storing its matching state value.
