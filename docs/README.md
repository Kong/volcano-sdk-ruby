---
title: Ruby SDK
description: Install the Volcano Ruby SDK and authenticate a user from a Ruby application.
order: 1
---

Use `volcano-sdk` for authentication, database queries, storage, functions, logs, locks, and realtime events.
REST calls are synchronous and raise typed exceptions on failure.
Ruby 3.2 or later is required; CI tests Ruby 3.2 and 3.4.

## Install the published gem

Add the [RubyGems package](https://rubygems.org/gems/volcano-sdk) to your application:

```bash
bundle add volcano-sdk
```

For a new directory without a Gemfile, run `bundle init` first.
Require the package with `require "volcano"`.

## Sign in and read a profile

Create a project, enable [email and password authentication](/platform/authentication/configuring-auth-methods), and create a user with a confirmed email when your project requires confirmation.
Use that project's [anonymous key](/platform/authentication/security/anon-keys).
Set `VOLCANO_ANON_KEY`, `VOLCANO_USER_EMAIL`, and `VOLCANO_USER_PASSWORD` in your environment.
Set `VOLCANO_API_URL` only when using a different API endpoint, such as local mode.

Save this as `quickstart.rb`:

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
begin
  user = client.auth.user
  raise "Unexpected user" unless user.id == session.user_id

  puts "Signed in as #{user.email}"
ensure
  client.auth.sign_out
end
```

Run it with `bundle exec ruby quickstart.rb`.
It signs in, fetches the server-validated profile, prints the user's email, revokes its server session, and clears the local session.
An invalid email or password raises `Volcano::Error::AuthenticationError`; failed network requests raise `Volcano::Error::TransportError`.
Both inherit from `Volcano::Error::VolcanoError`.

## Keep authentication scoped to one user

A client holds its current session in memory.
Use a separate client for each independent user session; do not share one mutable client across users in a web server.
`client.current_session` and `client.auth.current_session` read the local immutable snapshot without a request.
Use `client.auth.user` when you need a server-validated profile; `get_user` is an alias.
Successful profile operations update the cached user while preserving the current credentials.
If `user`, `update_user`, `convert_anonymous`, or `confirm_email_change` receives an HTTP 401 and the session has a usable refresh token, the client refreshes once and retries with the original request values.
These operations do not retry other HTTP failures or ambiguous network failures, and they never retry under a replacement session.

`sign_up` returns an acknowledgement without signing in by default.
Pass `sign_in_when_allowed: true` to sign in only when the project does not require email confirmation.
To adopt an existing session, assign a `Volcano::Session` containing its access token, refresh token, and user ID to `client.auth.current_session`.
The SDK does not persist tokens for you.

For operations that require a [service key](/platform/authentication/security/service-keys), pass `service_key` to the constructor in trusted server code.
Keep service keys and user credentials out of source control and client applications.

## Use a supplied access token

For a server request that already carries a user's access token, create a client for that request:

```ruby
require "volcano"

def load_request_user(access_token)
  client = Volcano::Client.new(
    anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
    access_token: access_token
  )
  client.auth.user
end
```

Call this helper from your request handler with the bearer token from that request.
For a Volcano function, use the access token in `event.fetch("__volcano_auth")` supplied for that invocation.
The helper validates the token with Volcano before returning the user.

Once a user identity has been validated, a refresh response for another user is rejected and leaves the current credentials unchanged.
Construction makes no request and does not persist credentials.
The initial snapshot has `nil` refresh credentials, user ID, and cached user.
A successful profile read fills in the validated identity and cached user while retaining the supplied access token.
Without a refresh token, an HTTP 401 remains an authentication error, `refresh_session` raises `Volcano::Error::AuthenticationError`, and `sign_out` revokes the server session identified by the access token before clearing local state.
Before opening realtime, the client validates an unknown identity with `auth.user`.
Sign-out uses the access-token session even when a refresh token was supplied. An expired access token can make revocation fail; local clearing still occurs and the error is raised.
Pass `refresh_token` alongside `access_token` when the client should refresh that session.
A revocation failure is reported after local clearing; it does not prove that copied tokens are invalid.
Assigning `auth.current_session` still requires complete credentials and identity.

## Use the rest of the API

The SDK repository contains [examples for every public facade](https://github.com/Kong/volcano-sdk-ruby#create-a-client), including database filters and mutations, resumable uploads, function invocation, log queries, lock guards, and realtime presence and database changes.
Follow the realtime examples to connect and disconnect channels within their supported async task lifecycle.

See [release notes](https://github.com/Kong/volcano-sdk-ruby/releases) for version changes and [GitHub issues](https://github.com/Kong/volcano-sdk-ruby/issues) to report a problem.
Include the gem version, Ruby version, and a minimal reproduction without credentials.
