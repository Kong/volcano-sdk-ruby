---
title: Realtime
description: Send broadcasts, observe presence, and receive database changes with Ruby async channels.
order: 8
---

Subscribe to a broadcast channel and send a JSON publication inside an Async reactor.
Sign in with the [quickstart credentials](./README.md) and enable the project's realtime capabilities and access policies.

```ruby
require "async"
require "volcano"

client = Volcano::Client.new(
  anon_key: ENV.fetch("VOLCANO_ANON_KEY"),
  api_url: ENV.fetch("VOLCANO_API_URL", "https://api.volcano.dev")
)
client.auth.sign_in(
  email: ENV.fetch("VOLCANO_USER_EMAIL"),
  password: ENV.fetch("VOLCANO_USER_PASSWORD")
)
Async do |task|
  channel = client.realtime.channel("updates")
  channel.on("message") { |message| puts message }
  begin
    channel.subscribe
    channel.send(event: "message", value: "hello")
    task.sleep(2)
  ensure
    client.realtime.disconnect
  end
end.wait
```

`subscribe` waits for the server acknowledgement.
Channel names receive their type prefix, so `updates` becomes `broadcast:updates`.
Run realtime operations inside the same Async reactor for that client.
The following channel examples belong inside an `Async` block with an authenticated `client`.

## Pause or remove channels

```ruby
channel = client.realtime.channel("updates")
channel.on("message") { |message| puts message }
channel.subscribe
channel.unsubscribe
channel.subscribe
client.realtime.remove_channel("updates")
```

Unsubscribe pauses delivery while retaining handlers and the in-memory broadcast recovery position.
Subscribe resumes and requests missed broadcasts when retained history is available.
Removal forgets the channel and its recovery position.
`remove_all_channels` removes all channels while leaving the shared connection available; `disconnect` closes it.
Application code owns any work its callbacks start and should await that work during shutdown.

## Observe presence

```ruby
lobby = client.realtime.channel("lobby", type: :presence)
lobby.on_presence_sync { |state| puts "Online #{state.length}" }
lobby.on("join") { |info| puts "Joined #{info.user}" }
lobby.on("leave") { |info| puts "Left #{info.user}" }
lobby.subscribe
lobby.track("status" => "online")
puts lobby.tracked_state
puts lobby.presence_state
client.realtime.remove_channel("lobby", type: :presence)
```

Presence identity and metadata come from the authenticated user.
`track` stores optional local application state; it does not replace server-managed presence metadata.
The roster maps connection IDs to immutable client identity and user metadata snapshots.
One user can have several connections. The original sync callback observes connections joining and leaving.
`get_presence_state` is an alias for `presence_state`.
Presence rebuilds its current roster after reconnection.

## Subscribe to database changes

Use an existing `app` database and `public.messages` table with realtime and suitable Row-Level Security policies configured:

```ruby
client.realtime.database_name = "app"
changes = client.realtime.channel("public:messages", type: :postgres)
changes.on_postgres_changes("INSERT", schema: "public", table: "messages") do |change|
  puts change.record
end
changes.subscribe
Async::Task.current.sleep(30)
client.realtime.remove_channel("public:messages", type: :postgres)
```

Insert a row from another client during the listening period.
Matching insert and update notifications can fetch full rows using the subscription's user token.
Compatible row lookups are batched while publication order is preserved.
Defaults are a 20 millisecond window and 50 rows; set `fetch_batch_window_ms:` and `fetch_max_batch_size:` on the channel to change them.
Both values must be positive integers, and the maximum batch size is 128.
Use `auto_fetch: false` to retain lightweight notifications without row lookups.
A failed lookup reports an error and delivers the original lightweight change.
Deletes use `old_record` or the row ID and do not query the database.

## Handle connection changes

```ruby
stop_errors = client.realtime.on_error { |context| warn context.message }
stop_connected = client.realtime.on_connect { |context| puts context.client }
stop_disconnected = client.realtime.on_disconnect { |context| puts context.reason }
```

Each registration returns an idempotent unsubscribe callable.
Callbacks receive immutable contexts and run outside connection processing.
Unexpected transport loss reconnects with bounded backoff and restores active subscriptions.
Broadcast recovery stays within one client lifetime and one authenticated session lineage; it is not persisted across processes.
Postgres subscriptions do not recover missed publications.
After changing users, disconnect before subscribing for the new session.
Do not use realtime delivery as a durable record of every database change.
