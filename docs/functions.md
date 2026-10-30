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

The SDK resolves the function's invocation endpoint and caches it for the lifetime provided by Volcano. Repeated resolution of a missing name raises a new `Volcano::Error::NotFoundError` with the original message, status, and error code while the cached miss remains valid.
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

## Start and follow a durable execution

A durable execution can run for up to 366 days. Starting one returns a handle instead of waiting for its result:

```ruby
handle = client.durable.start(
  "charge-order",
  { order_id: "order-9" },
  execution_name: "order-9"
)
token = handle.client_token

execution = client.durable.get_from_application("charge-order", handle.id, client_token: token)
client.durable.stop_from_application("charge-order", handle.id, client_token: token)
```

`start`, `get_from_application`, and `stop_from_application` use the same credential as `functions.invoke`: the active session, then a service key, then the anonymous key. An execution name makes a start idempotent. The start that creates an execution returns its `client_token`; a repeated start returns nil there. Inspecting the execution masks the token.

A service key holding `*`, the default, reads and stops any execution of the project. A signed-in user reaches the executions they started without the client token. An anonymous key, a user who did not start the execution, or a service key scoped to a list without `*` passes `client_token:`. An anonymous key or a service key scoped without `*` also needs `functions.invoke`; without it the call raises `Volcano::Error::PermissionDeniedError`. The function's visibility must also admit the credential: an anonymous key on an `authenticated` function raises `Volcano::Error::PermissionDeniedError`, even with the token, and a `private` function raises `Volcano::Error::NotFoundError` for every credential but a service key. An execution the credential cannot reach raises `Volcano::Error::NotFoundError`, as a missing one does, and so does one still `pending` unless the credential is a service key holding `*`. Reads never return `client_token`, so keep the one the start returned.

`stop_from_application` and `stop` return after the stop request is accepted, often while the execution still reports `running`; poll the matching read until `terminal?` is true. Stopping an execution that already finished returns the state it settled in. A `stop_from_application` answered with a `503` `Volcano::Error::ServerError` may already have been sent, so read the execution before stopping it again.

Tooling that manages a project uses the owner-scoped `get`, `list`, and `stop`, which reach any execution without a client token:

```ruby
owner_client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev"),
  access_token: ENV.fetch("VOLCANO_PLATFORM_TOKEN")
)
execution = owner_client.durable.get(project_id, "charge-order", handle.id)
page = owner_client.durable.list(project_id, "charge-order", status: "running")
owner_client.durable.stop(project_id, "charge-order", handle.id)
```

Call them from a trusted backend with the project owner's platform user token or a project access token; a `read_only` token can read and list but not stop. Auth-user sessions, anonymous keys, and service keys are not accepted.

`list` returns executions and pagination metadata. A successful response must include `data`, `page`, `limit`, `total`, and `has_more` with the API's declared types. Missing or malformed fields raise `TypeError`; a complete response with `data: []` returns an empty execution list.

Ruby can start and manage durable functions written in JavaScript or Python. The Ruby SDK has no durable authoring API.

## Decide durable approvals

A durable function written in JavaScript or Python can wait for a person to approve or deny a request. Ruby reads and decides those approvals:

```ruby
approvals = owner_client.durable.approvals
page = approvals.list(project_id, status: "pending", function: "refunds")
approvals.approve(project_id, page.approvals.first.id, comment: "Matches the invoice")
approvals.deny(project_id, approval_id)
stats = approvals.stats(project_id, from: Time.now - (7 * 86_400))
```

`list` and `get` return `DurableApproval` records; `stats` returns counts by status, the approval rate, and decision times for a window that defaults to the last 30 days. `daily` entries carry `YYYY-MM-DD` UTC dates.

An approval's `decision` is nil unless it was approved or denied. `decision.decided_by` is nil once the deciding account is deleted, so read it with `decided_by&.email`.

Reads accept the project owner's platform user token or a project access token. Decisions require a person, so a project access token raises `Volcano::Error::PermissionDeniedError`, a subclass of `Volcano::Error::AuthenticationError`. A conflicting decision, or deciding an expired or cancelled approval, raises `Volcano::Error::ConflictError` with `code` set to `approval_decided`, `approval_expired`, or `approval_cancelled`; repeating the same decision returns the approval unchanged. An unknown approval raises `Volcano::Error::NotFoundError`. Malformed responses raise `TypeError`.

## Message a durable execution

A durable function written in JavaScript or Python can wait for a named message and publish messages of its own. Ruby sends, lists, and follows them. Here a signed-in user starts the execution, so it reaches it without the client token:

```ruby
require "async"

client.auth.sign_in(
  email: ENV.fetch("VOLCANO_USER_EMAIL"),
  password: ENV.fetch("VOLCANO_USER_PASSWORD")
)
handle = client.durable.start("onboarding", { account_id: "account-7" })
messages = client.durable.messages

messages.send_message("onboarding", handle.id, "documents-uploaded", { count: 3 }, idempotency_key: "upload-42")
page = messages.list("onboarding", handle.id, direction: "out", after: 0, limit: 100)

Async do
  subscription = messages.subscribe("onboarding", handle.id) do |message|
    puts [message.seq, message.name, message.data]
  end
  # ...
  subscription.unsubscribe
ensure
  client.realtime.disconnect
end.wait
```

`send_message` queues the message until a wait for its name takes it, and returns the stored `DurableMessage`: its `status` is `delivered` when a wait took it at once, `delivering` while the handover to that wait is still being confirmed, and `queued` otherwise. A name is 1 to 237 printable ASCII characters; `data` is any JSON value up to 64 KiB. Sending again with an `idempotency_key` the same sender has used on the execution returns the stored message in its current status and sends nothing; another sender's keys never collide with it. Sending to an execution that has ended raises `Volcano::Error::ConflictError` with `code` `execution_not_running`, and sending to one already holding 100 messages no wait has taken raises it with `too_many_queued_messages`.

`list` returns both directions, oldest first, filtered by `direction` (`in` or `out`), `name`, `after` (a `seq`), and `limit` (1 to 500, default 100). `seq` orders an execution's messages but can skip numbers, so read the next page with `after` set to the last message's `seq` while `has_more` is true.

`subscribe` delivers what the execution publishes, once each, in `seq` order, and one block call at a time: first the messages it published before the call, then live ones. After a reconnect, or a live message that shows an earlier one was lost, it reads back the missing ones before live delivery resumes. A read-back that fails is reported to `realtime.on_error` and retried, backing off to every 30 seconds, while the live messages after the gap wait. `realtime.remove_all_channels` and `realtime.disconnect` end the subscription, and a read-back still in flight delivers nothing; during the first read-back, `subscribe` then raises `Volcano::Realtime::ClosedError`. The subscription belongs to the session that opened it: once the client signs out, signs in again, or sets another session, it reads and delivers nothing more, the next read-back, delivery, or reconnect leaves the execution's channel, and raises `Volcano::Error::SessionChangedError`, reported to `realtime.on_error`, or from `subscribe` during its first read-back. Subscribing on a realtime connection an earlier session opened raises it too, and closes that connection so the next call reconnects as the current session. A token refresh keeps it. A reconnect the server refuses to restore the subscription on, as when the execution is no longer visible to the session, ends it too: the refusal is reported to `realtime.on_error` once, as a `Volcano::Realtime::ServerError` with the server's `code`, and the execution can be subscribed to again. A refusal the server marks `temporary?` is retried instead. It runs on the client's realtime connection, so call it inside an Async reactor with a signed-in session. A block that raises during the first read-back ends the subscription before it is called again, and raises from `subscribe`; one that raises later, on a live message or during a read-back, is reported to `realtime.on_error`, and delivery goes on with the next message. A second subscription to the same execution raises `Volcano::Realtime::DuplicateSubscriptionError` until the first unsubscribes.

These calls use the application route with the same credential `start` uses. The service key reaches every execution. A signed-in user reaches executions they started, and the anon key, or another user, reaches one by passing its `client_token:`. The function must be visible to the credential: public for the anon key, public or authenticated for a user. The anon key on an authenticated function raises `Volcano::Error::PermissionDeniedError`; any other execution the credential cannot reach raises `Volcano::Error::NotFoundError`. Only the start that creates an execution returns the token, so a lost start response loses it.

Pass `project_id:` to `send_message`, `list`, or `subscribe` to use the owner's route with the project owner's platform user token or a project access token instead; `subscribe` reads back over it, and a read-only token can list but not send.
