---
title: Distributed locks
description: Coordinate Ruby workers with project-scoped lock leases, renewal, and fencing tokens.
order: 7
---

Acquire a project-scoped lease from trusted server code using a service key.
Set `VOLCANO_ANON_KEY` and `VOLCANO_SERVICE_KEY` for the same project.

```ruby
require "volcano"

client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  service_key: ENV.fetch("VOLCANO_SERVICE_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev")
)
lease = client.locks.acquire("daily-report", ttl: 30)
begin
  puts "Lease acquired #{lease.fencing_token}"
ensure
  client.locks.release("daily-report", lease)
end
```

`acquire` returns an immutable `Volcano::LockLease` containing the key, ownership token, expiration, and fencing token.
Release and renew using that lease; the ownership token identifies the holder.
A competing owner can cause `Volcano::Error::ConflictError`.

## Renew or inspect a lease

```ruby
state = client.locks.get("daily-report")
puts [state.held, state.expires_at, state.fencing_token]

lease = client.locks.acquire("daily-report", ttl: 30)
begin
  lease = client.locks.renew("daily-report", lease, ttl: 60)
ensure
  client.locks.release("daily-report", lease)
end
```

`get` reports availability without acquiring the lock.
`renew` returns a new immutable lease, so retain its return value.

## Renew for the duration of a block

```ruby
client.locks.with_lock("daily-report", ttl: 30) do |guard|
  puts "Current fence #{guard.lease.fencing_token}"
  raise "Lock ownership was lost" if guard.lost?
end
```

The block helper renews in the background and attempts to release its latest lease on exit.
`guard.lease` reads the latest lease; `guard.lost?` checks ownership loss, and `guard.wait_lost(timeout: 1.0)` waits up to one second for it.
Stop protected work when ownership is lost.
Use fencing tokens in the protected data store so an expired worker cannot overwrite work performed by a newer holder.
Lease renewal alone cannot stop application code that is already running.

## Recover an abandoned lock

`client.locks.force_release("daily-report")` removes the current lease without its ownership token.
Use this only for administrative recovery with fencing enforced by the protected resource.

## Recover an uncertain acquisition

Acquisition retries a transport failure or HTTP 503 once with the same ownership
token, request ID, key, TTL, and credential. Other HTTP errors are not retried.
For recovery after that retry also fails, generate and retain identifiers before
acquiring, then reuse them for the same acquisition attempt:

```ruby
require "securerandom"

owner_token = SecureRandom.uuid
request_id = SecureRandom.uuid
lease = client.locks.acquire(
  "daily-report", ttl: 30, token: owner_token, request_id: request_id
)
```

Every lock method accepts `request_id:`. `with_lock` also accepts `token:` and
`request_id:` for acquisition; its renewal and release calls use new request IDs.

Use a new ownership token for a new lease after release or expiry. Keep ownership
tokens private. A failed response does not prove the server failed to acquire;
reuse the original token to recover the outcome rather than starting a new owner.
