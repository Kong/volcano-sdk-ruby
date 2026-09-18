---
title: Functions
description: Invoke deployed Volcano functions from Ruby and inspect their response status, headers, and data.
order: 5
---

Invoke a deployed function by its name.
This example assumes a public function named `hello` that accepts a JSON object.
Grant the anonymous key the explicit `functions.invoke` permission; the default
authentication-only permissions do not allow invocation. See [anonymous keys](/platform/authentication/security/anon-keys).

```ruby
require "volcano"

client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev")
)
result = client.functions.invoke("hello", name: "Ada")
puts result.status
puts result.data
puts result.version
```

The SDK resolves the function's invocation endpoint and caches it for the lifetime provided by Volcano.
Allow outbound requests to the resolved function domain as well as the API host.
Deployments without a separate function domain use the API invocation endpoint.

## Choose the invocation identity

The SDK uses the current session's access token, including a supplied `access_token`, before a configured service key or anonymous key.
A rejected or unsupported session token does not fall back to a key. Use an end-user access token when the function requires a user identity.
Use the [quickstart](./README.md) to sign in before invoking a function that requires a user.
An invocation authorized only by the anonymous key has no user identity.

Supply `service_key:` to the client constructor for trusted server operations that require it.
Use a separate client for each independent user session.

## Recover a rejected session

Function resolution and invocation recover from a platform HTTP 401 before dispatch:
the SDK refreshes the captured session and retries the rejected request once.
Concurrent calls share successful recovery. Replacing or signing out that session
prevents replay under another identity. The call preserves its original payload values.
A function's own response, HTTP 403, or a network failure never triggers this retry.
Anonymous and service keys do not refresh.

## Read the result

`Volcano::FunctionResponse` is immutable and exposes `status`, `headers`, `version`, and `data`.
The payload sent to `invoke` must be a hash representing a JSON object; omitting it sends an empty object.
Response data can be a JSON object, array, scalar, text, or `nil` for an empty body.
JSON objects and arrays are immutable, and invalid JSON is returned as text.

A function's own non-success response is returned as a result when Volcano confirms the function ran.
Check `result.status` to handle those application errors.
Non-success platform HTTP responses before dispatch raise typed SDK exceptions such as `Volcano::Error::NotFoundError` or `Volcano::Error::AuthenticationError`.

If a cached function identity no longer exists, the SDK resolves the name again and retries once only when the platform confirms no function was dispatched.
A function's own HTTP 404 does not trigger another invocation.
Network failures do not establish whether a function ran; do not blindly retry operations with side effects.

Invalid invocation arguments and malformed successful resolution responses can raise `ArgumentError` or `TypeError`.
